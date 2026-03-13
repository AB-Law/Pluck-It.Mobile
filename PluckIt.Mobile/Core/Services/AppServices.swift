import Foundation
import Combine

@MainActor
final class AppServices: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private var cancellables: Set<AnyCancellable> = []

    let runtimeConfiguration: RuntimeConfiguration
    let authService: AuthService
    let tokenExchangeClient: APIClient
    let apiClient: APIClient
    let processorClient: APIClient
    let networkMonitor: NetworkMonitor
    let wardrobeService: WardrobeService
    let collectionService: CollectionService
    let discoverService: DiscoverService
    let vaultInsightsService: VaultInsightsService
    let profileService: ProfileService
    let stylistService: StylistService
    let digestService: DigestService

    init(runtimeConfiguration: RuntimeConfiguration) {
        self.runtimeConfiguration = runtimeConfiguration
        self.networkMonitor = NetworkMonitor()
        let debugEnabled = runtimeConfiguration.networkDebugEnabled
        self.tokenExchangeClient = APIClient(
            baseUrl: runtimeConfiguration.apiBaseUrl,
            debugLoggingEnabled: debugEnabled
        )
        self.authService = AuthService(
            runtimeConfiguration: runtimeConfiguration,
            tokenExchangeClient: tokenExchangeClient
        )
        self.authService.bootstrap()
        let authService = self.authService

        self.apiClient = APIClient(
            baseUrl: runtimeConfiguration.apiBaseUrl,
            tokenProvider: { [weak authService] in
                await authService?.currentToken()
            },
            debugLoggingEnabled: debugEnabled
        )
        self.processorClient = APIClient(
            baseUrl: runtimeConfiguration.processorBaseUrl,
            tokenProvider: { [weak authService] in
                await authService?.currentToken()
            },
            debugLoggingEnabled: debugEnabled
        )

        self.wardrobeService = WardrobeService(client: apiClient)
        self.collectionService = CollectionService(client: apiClient)
        self.discoverService = DiscoverService(client: processorClient)
        self.vaultInsightsService = VaultInsightsService(client: processorClient)
        self.profileService = ProfileService(client: apiClient)
        self.stylistService = StylistService(client: processorClient)
        self.digestService = DigestService(client: processorClient)

        self.authService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    convenience init() {
        self.init(runtimeConfiguration: RuntimeConfiguration())
    }
}
