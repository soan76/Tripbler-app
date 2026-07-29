import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let googleMapsApiKey = Bundle.main.object(
      forInfoDictionaryKey: "GoogleMapsApiKey"
    ) as? String

    if let googleMapsApiKey = googleMapsApiKey,
       !googleMapsApiKey.isEmpty,
       !googleMapsApiKey.contains("$(") {
      GMSServices.provideAPIKey(googleMapsApiKey)
    } else {
      print("Google Maps iOS API key is missing. Check ios/Flutter/Secrets.xcconfig")
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}