#!/usr/bin/env python3
"""
PluckIt — CatVTON local inference server.

Launched by MacTryOnSidecar as a subprocess. Exposes a minimal HTTP API
on localhost so the Swift app can submit try-on jobs without any cloud
dependency. The server loads models once on startup; subsequent requests
reuse the loaded pipeline.

Endpoints:
  GET  /health   → {"ready": bool, "device": str}
  POST /try-on   → PNG image bytes (multipart: person_image, garment_image, cloth_type)
"""

import sys
import os
import io
import json
import time
import threading
import logging
from datetime import datetime, timezone
from pathlib import Path

# ── Paths injected by the Swift launcher ──────────────────────────────────────
REPO_DIR    = os.environ.get("TRYON_REPO_DIR", "")
WEIGHTS_DIR = Path(os.environ.get("TRYON_WEIGHTS_DIR",
                   Path.home() / "Library/Application Support/PluckIt/tryon/weights"))
CATVTON_DIR = WEIGHTS_DIR / "catvton"
SUPPORT_DIR = WEIGHTS_DIR.parent          # ~/Library/Application Support/PluckIt/tryon
METRICS_LOG = SUPPORT_DIR / "metrics.jsonl"

# Add cloned CatVTON repo to import path so `from model.pipeline import …` works
if REPO_DIR:
    sys.path.insert(0, REPO_DIR)

import torch
import numpy as np
from PIL import Image
from flask import Flask, request, jsonify, send_file

logging.basicConfig(
    level=logging.INFO,
    format="[tryon] %(levelname)s %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger(__name__)

app   = Flask(__name__)
_lock = threading.Lock()

_pipeline      = None   # CatVTONPipeline
_seg_pipeline  = None   # HF image-segmentation for cloth mask generation
_device        = "mps" if torch.backends.mps.is_available() else "cpu"
_load_error    = None   # surfaced through /health if loading fails

# float16 halves memory vs float32; bfloat16 is more numerically stable on MPS
_weight_dtype  = torch.bfloat16 if torch.backends.mps.is_available() else torch.float16

# Allow MPS to use unified memory without a hard cap
if torch.backends.mps.is_available():
    os.environ.setdefault("PYTORCH_MPS_HIGH_WATERMARK_RATIO", "0.0")

INFER_H, INFER_W = 768, 576
SCHEDULER_NAME   = "DPMSolverMultistep+Karras"


def _fit_and_pad(img: Image.Image, w: int, h: int, bg: tuple = (255, 255, 255)) -> Image.Image:
    """Scale image to fit within w×h preserving aspect ratio, then pad to exact size."""
    img.thumbnail((w, h), Image.LANCZOS)
    canvas = Image.new("RGB", (w, h), bg)
    x = (w - img.width)  // 2
    y = (h - img.height) // 2
    canvas.paste(img, (x, y))
    return canvas


# ── Labels produced by mattmdjaga/segformer_b2_clothes ───────────────────────
_UPPER_LABELS  = {"Upper-clothes", "Coat", "Jacket", "Shirt", "Dress", "Blouse"}
_LOWER_LABELS  = {"Pants", "Skirt", "Shorts", "Leggings"}


# ── Metrics ───────────────────────────────────────────────────────────────────

def _write_metric(record: dict) -> None:
    try:
        with open(METRICS_LOG, "a") as f:
            f.write(json.dumps(record) + "\n")
    except Exception as e:
        log.warning(f"Could not write metrics: {e}")


# ── Model loading (called once in a background thread) ───────────────────────

def _load_models() -> None:
    global _pipeline, _seg_pipeline, _load_error

    t0 = time.perf_counter()
    try:
        log.info(f"Device: {_device}  dtype: {_weight_dtype}")

        log.info("Loading cloth-segmentation model…")
        from transformers import pipeline as hf_pipeline
        _seg_pipeline = hf_pipeline(
            "image-segmentation",
            model="mattmdjaga/segformer_b2_clothes",
            device=-1,   # CPU — fast enough and avoids MPS memory pressure
        )

        log.info("Loading CatVTON pipeline…")
        from model.pipeline import CatVTONPipeline   # from cloned repo
        _pipeline = CatVTONPipeline(
            base_ckpt="runwayml/stable-diffusion-inpainting",
            attn_ckpt=str(CATVTON_DIR),
            attn_ckpt_version="mix",
            weight_dtype=_weight_dtype,
            use_tf32=False,          # tf32 is CUDA-only
            device=_device,
            skip_safety_check=True,
        )

        # ── Swap to DPM++ 2M Karras: same quality in ~20 steps vs DDIM's 30 ──
        from diffusers import DPMSolverMultistepScheduler
        _pipeline.noise_scheduler = DPMSolverMultistepScheduler.from_config(
            _pipeline.noise_scheduler.config,
            use_karras_sigmas=True,
        )
        log.info("Scheduler: DPMSolverMultistep (Karras)")

        elapsed = time.perf_counter() - t0
        log.info(f"All models ready in {elapsed:.1f}s.")
        _write_metric({
            "event":          "model_load",
            "timestamp":      datetime.now(timezone.utc).isoformat(),
            "load_time_s":    round(elapsed, 2),
            "device":         _device,
            "dtype":          str(_weight_dtype),
            "scheduler":      SCHEDULER_NAME,
            "infer_res":      f"{INFER_W}x{INFER_H}",
            "attn_chunk":     1024,
        })

    except Exception:
        import traceback
        _load_error = traceback.format_exc()
        log.error(f"Model loading failed:\n{_load_error}")


# ── Mask generation ───────────────────────────────────────────────────────────

def _generate_mask(person_image: Image.Image, cloth_type: str) -> Image.Image:
    """
    Returns a binary PIL mask (L mode) for the clothing region to replace.
    Uses the cloth-segmentation model to locate the target garment class.
    Falls back to a centre-torso rectangle if segmentation returns nothing.
    """
    if cloth_type == "upper":
        targets = _UPPER_LABELS
    elif cloth_type == "lower":
        targets = _LOWER_LABELS
    else:
        targets = _UPPER_LABELS | _LOWER_LABELS

    results = _seg_pipeline(person_image)

    mask = np.zeros((person_image.height, person_image.width), dtype=np.uint8)
    found = False
    for r in results:
        if r["label"] in targets:
            seg_arr = np.array(r["mask"].convert("L"))
            mask = np.maximum(mask, seg_arr)
            found = True

    if not found:
        log.warning("Cloth segmentation found no matching labels — using centre-torso fallback.")
        h, w = person_image.height, person_image.width
        mask[int(h * 0.20):int(h * 0.65), int(w * 0.15):int(w * 0.85)] = 255

    return Image.fromarray(mask, mode="L")


# ── HTTP endpoints ────────────────────────────────────────────────────────────

@app.route("/health")
def health():
    return jsonify({
        "status":    "ok",
        "ready":     _pipeline is not None,
        "device":    _device,
        "scheduler": SCHEDULER_NAME,
        "res":       f"{INFER_W}x{INFER_H}",
        "error":     _load_error,
    })


@app.route("/try-on", methods=["POST"])
def try_on():
    if _pipeline is None:
        return jsonify({"error": "Models not loaded yet — please wait."}), 503

    if "person_image" not in request.files or "garment_image" not in request.files:
        return jsonify({"error": "Multipart fields person_image and garment_image are required."}), 400

    cloth_type   = request.form.get("cloth_type", "upper")
    num_steps    = int(request.form.get("num_steps", 20))     # 20 steps with DPM++ ≈ 30 DDIM
    guidance     = float(request.form.get("guidance_scale", 3.5))
    seed         = int(request.form.get("seed", 42))

    person_bytes  = request.files["person_image"].read()
    garment_bytes = request.files["garment_image"].read()

    person_image  = Image.open(io.BytesIO(person_bytes)).convert("RGB")
    raw_garment   = Image.open(io.BytesIO(garment_bytes))
    if raw_garment.mode == "RGBA":
        garment_image = Image.new("RGB", raw_garment.size, (255, 255, 255))
        garment_image.paste(raw_garment, mask=raw_garment.split()[3])
    else:
        garment_image = raw_garment.convert("RGB")

    person_image  = _fit_and_pad(person_image,  INFER_W, INFER_H)
    garment_image = _fit_and_pad(garment_image, INFER_W, INFER_H)

    t_seg = time.perf_counter()
    log.info(f"Generating mask (cloth_type={cloth_type})…")
    mask = _generate_mask(person_image, cloth_type)
    seg_time = time.perf_counter() - t_seg
    log.info(f"Mask generated in {seg_time:.2f}s")

    log.info(f"Running inference (steps={num_steps}, guidance={guidance}, seed={seed}, "
             f"size={INFER_W}×{INFER_H}, scheduler=DPM++Karras)…")
    t_infer = time.perf_counter()
    with _lock:
        generator = torch.Generator(device=_device).manual_seed(seed)
        with torch.inference_mode():
            result = _pipeline(
                image=person_image,
                condition_image=garment_image,
                mask=mask,
                num_inference_steps=num_steps,
                guidance_scale=guidance,
                height=INFER_H,
                width=INFER_W,
                generator=generator,
            )[0]
        if torch.backends.mps.is_available():
            torch.mps.empty_cache()

    infer_time = time.perf_counter() - t_infer
    total_time = seg_time + infer_time
    sps        = infer_time / num_steps

    log.info(f"Inference complete in {infer_time:.1f}s  "
             f"({sps:.2f}s/step, {num_steps} steps)  "
             f"total={total_time:.1f}s")

    _write_metric({
        "event":          "inference",
        "timestamp":      datetime.now(timezone.utc).isoformat(),
        "cloth_type":     cloth_type,
        "num_steps":      num_steps,
        "guidance_scale": guidance,
        "seed":           seed,
        "res":            f"{INFER_W}x{INFER_H}",
        "scheduler":      SCHEDULER_NAME,
        "attn_chunk":     1024,
        "seg_time_s":     round(seg_time,   2),
        "infer_time_s":   round(infer_time, 2),
        "total_time_s":   round(total_time, 2),
        "s_per_step":     round(sps,        2),
        "device":         _device,
    })

    buf = io.BytesIO()
    result.save(buf, format="PNG")
    buf.seek(0)
    return send_file(buf, mimetype="image/png")


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 7433
    threading.Thread(target=_load_models, daemon=True).start()
    app.run(host="127.0.0.1", port=port, threaded=False)
