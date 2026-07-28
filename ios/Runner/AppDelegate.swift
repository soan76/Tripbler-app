import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let googleMapsApiKey = Bundle.main.object(
      forInfoDictionaryKey: "GoogleMapsApiKey"
    ) as? String

    if let googleMapsApiKey = googleMapsApiKey {
      GMSServices.provideAPIKey(googleMapsApiKey)
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
