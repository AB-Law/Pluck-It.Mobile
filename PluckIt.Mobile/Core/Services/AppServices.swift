import Foundation
import Combine

@MainActor
final class AppServices: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    let runtimeConfiguration: RuntimeConfiguration
    let authService: AuthService
    let apiClient: APIClient
    let processorClient: APIClient
    let networkMonitor: NetworkMonitor
    let wardrobeService: WardrobeService
    let collectionService: CollectionService
    let discoverService: DiscoverService
    let vaultInsightsService: VaultInsightsService
    let profileService: ProfileService

    init(runtimeConfiguration: RuntimeConfiguration) {
        self.runtimeConfiguration = runtimeConfiguration
        self.networkMonitor = NetworkMonitor()
        let debugEnabled = runtimeConfiguration.networkDebugEnabled
        self.authService = AuthService(runtimeConfiguration: runtimeConfiguration)
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
        self.vaultInsightsService = VaultInsightsService(client: apiClient)
        self.profileService = ProfileService(client: apiClient)
    }

    convenience init() {
        self.init(runtimeConfiguration: RuntimeConfiguration())
    }
}
