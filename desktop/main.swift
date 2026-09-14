// RV 桌面壳（macOS）：WKWebView 装载编译产物
// 支持两种模式：
//   打包模式（默认）  加载 .app/Contents/Resources/index.html
//   开发模式          可执行文件 --dev http://localhost:4402/xxx.html
//                    （连接 rv dev 服务器，桌面应用内同样享受热刷新）
import Cocoa
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var webView: WKWebView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rect = NSRect(x: 0, y: 0, width: 460, height: 640)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window?.title = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "RV"
        window?.center()
        window?.minSize = NSSize(width: 360, height: 320)

        let web = WKWebView(frame: rect, configuration: WKWebViewConfiguration())
        let args = CommandLine.arguments
        if args.count >= 3, args[1] == "--dev", let url = URL(string: args[2]) {
            web.load(URLRequest(url: url))
        } else if let resources = Bundle.main.resourceURL {
            let entry = resources.appendingPathComponent("index.html")
            web.loadFileURL(entry, allowingReadAccessTo: resources)
        }
        webView = web
        window?.contentView = web
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
