import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var splashScreenView: UIView?
  private var networkPermissionCompleted = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // 🌐 第一步：在Flutter启动前触发网络权限
    print("📱 [Native] APP启动 - 开始触发网络权限...")

    // 使用信号量阻塞等待网络权限处理完成
    let semaphore = DispatchSemaphore(value: 0)
    var permissionCompleted = false

    DispatchQueue.global(qos: .userInitiated).async {
      self.triggerNetworkPermission()
      permissionCompleted = true
      semaphore.signal()
    }

    // 等待网络权限处理完成（最多12秒）
    _ = semaphore.wait(timeout: .now() + 12.0)

    if permissionCompleted {
      print("✅ [Native] 网络权限处理完成，继续初始化")
    } else {
      print("⏱️ [Native] 网络权限处理超时，继续初始化")
    }

    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let splashChannel = FlutterMethodChannel(
      name: "com.hupc.hmusic/splash",
      binaryMessenger: controller.binaryMessenger
    )

    // 保持启动屏显示
    showSplashScreen()

    splashChannel.setMethodCallHandler { [weak self] (call, result) in
      if call.method == "hideSplash" {
        self?.hideSplashScreen()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func showSplashScreen() {
    guard let window = window,
          let launchScreenVC = UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController(),
          splashScreenView == nil else {
      return
    }

    splashScreenView = launchScreenVC.view
    splashScreenView?.frame = window.bounds
    window.addSubview(splashScreenView!)
  }

  private func hideSplashScreen() {
    DispatchQueue.main.async { [weak self] in
      UIView.animate(withDuration: 0.3, animations: {
        self?.splashScreenView?.alpha = 0
      }) { _ in
        self?.splashScreenView?.removeFromSuperview()
        self?.splashScreenView = nil
      }
    }
  }

  /// 触发iOS网络权限请求（国际区iOS需要）
  private func triggerNetworkPermission() {
    let semaphore = DispatchSemaphore(value: 0)

    // 创建一个简单的网络请求来触发权限弹窗
    guard let url = URL(string: "https://www.apple.com/library/test/success.html") else {
      print("❌ [Native] URL创建失败")
      semaphore.signal()
      return
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 5.0
    request.httpMethod = "GET"

    print("🌐 [Native] 发起网络请求以触发权限弹窗...")

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
      if let error = error {
        print("⚠️ [Native] 网络请求失败（可能用户拒绝或未授权）: \(error.localizedDescription)")
      } else {
        print("✅ [Native] 网络请求成功，权限已授权")
      }
      semaphore.signal()
    }

    task.resume()

    // 等待网络请求完成（最多等待10秒）
    let timeout = semaphore.wait(timeout: .now() + 10.0)

    if timeout == .timedOut {
      print("⏱️ [Native] 网络请求超时")
    }

    // 额外等待1秒，确保权限弹窗完全关闭，避免与本地网络权限弹窗冲突
    Thread.sleep(forTimeInterval: 1.0)

    print("✅ [Native] 网络权限处理完成")
  }
}
