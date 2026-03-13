import SwiftUI

struct ProfileOverlay: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var profile: UserProfile?
    @State private var loading = false
    @State private var errorText: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Active identity") {
                    Text(appServices.authService.identity?.userId ?? "Unknown")
                    if let email = appServices.authService.identity?.email {
                        Text(email)
                    }
                    Text(appServices.authService.identity?.isLocalMock == true ? "Local mock" : "Token-backed")
                        .foregroundStyle(PluckTheme.muted)
                }

                if loading {
                    Section {
                        ProgressView("Loading profile...")
                    }
                } else if let profile {
                    Section("Server profile") {
                        if let displayName = profile.displayName {
                            Text("Name: \(displayName)")
                        }
                        if let email = profile.email {
                            Text("Email: \(email)")
                        }
                    }
                } else if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        Task {
                            await loadProfile()
                        }
                    }
                }
            }
            .task {
                await loadProfile()
            }
            .frame(maxWidth: .infinity)
            .background(PluckTheme.background)
        }
    }

    private func loadProfile() async {
        loading = true
        errorText = nil
        do {
            profile = try await appServices.profileService.fetchProfile()
        } catch {
            errorText = String(describing: error)
        }
        loading = false
    }
}
