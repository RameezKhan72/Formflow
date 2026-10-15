"""Applies FormFlow's iOS settings to the folder made by
`flutter create --platforms ios` (camera text, AdMob id, SKAdNetwork ids,
portrait only, display name, iOS 15.5 minimum for ML Kit). Safe to re-run."""
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent / "ios"
plist = root / "Runner" / "Info.plist"
p = plist.read_text()


def add(key, value_xml):
    global p
    if "<key>%s</key>" % key in p:
        return
    p = p.replace("<dict>\n", "<dict>\n\t<key>%s</key>\n\t%s\n" % (key, value_xml), 1)


add("NSCameraUsageDescription", "<string>FormFlow uses the camera to see your body and correct your exercise form. Video is processed on the phone and never stored or uploaded.</string>")
add("NSMicrophoneUsageDescription", "<string>FormFlow does not record audio. iOS asks because the camera plugin can record video.</string>")
add("NSUserTrackingUsageDescription", "<string>This lets us show you more relevant ads. FormFlow Premium has no ads.</string>")
# Google's TEST AdMob app id: replace with yours before release (MONETIZATION.md)
add("GADApplicationIdentifier", "<string>ca-app-pub-3940256099942544~1458002511</string>")
add("SKAdNetworkItems", "<array>\n\t\t<dict>\n\t\t\t<key>SKAdNetworkIdentifier</key>\n\t\t\t<string>cstr6suwn9.skadnetwork</string>\n\t\t</dict>\n\t</array>")
p = re.sub(r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)", r"\1FormFlow\2", p)
# portrait only on iPhone (the app locks portrait at runtime too)
p = re.sub(r"(<key>UISupportedInterfaceOrientations</key>\s*<array>)(.*?)(</array>)",
           r"\1\n\t\t<string>UIInterfaceOrientationPortrait</string>\n\t\3", p, count=1, flags=re.S)
plist.write_text(p)

podfile = root / "Podfile"
template = (pathlib.Path(__file__).resolve().parent / "ios_Podfile").read_text()
podfile.write_text(template)

pbx = root / "Runner.xcodeproj" / "project.pbxproj"
if pbx.exists():
    s = pbx.read_text()
    s = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 15.5;", s)
    pbx.write_text(s)
print("patched", plist)
