import Foundation
import Observation
import Sparkle

/// 基于 Sparkle 2 的应用内更新控制器，仅封装 `SPUStandardUpdaterController`。
@MainActor
@Observable
final class UpdateController {
    private let updaterController: SPUStandardUpdaterController

    /// 是否每天自动检查新版本（默认开启）。
    var automaticallyChecksForUpdates: Bool {
        didSet {
            updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    /// 发现新版本后是否自动下载并在下次退出时安装（默认关闭）。
    var automaticallyDownloadsUpdates: Bool {
        didSet {
            updaterController.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        }
    }

    init() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates
    }

    /// 手动触发检查更新弹窗。
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
