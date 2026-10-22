/// Not available on this platform.
bool saveTextFile(String name, String text, String mime) => false;

/// Whether [pickTextFile] can open a file chooser here.
const canPickFile = false;

Future<String?> pickTextFile() async => null;
