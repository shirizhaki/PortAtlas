# App icon

The app icon is the Icon Composer document `Packaging/AppIcon.icon`: a USB-C socket with three
cable routes in the app's connection colors (data, display, power), built as Liquid Glass layers.
The layers are SVG files in `AppIcon.icon/Assets`. It contains no Apple logo or text.

Open `Packaging/AppIcon.icon` in Icon Composer (Xcode → Open Developer Tool → Icon Composer) to
adjust glass, shadow, translucency or the light, dark and tinted appearances.

`Scripts/build-app.sh` compiles the document into the app. Run `bash Scripts/build-icon.sh` after
editing it to refresh the flat fallback `Packaging/AppIcon.icns`.
