// Shared gradle constant, the way multi-module projects (e.g. NewPipe)
// declare the application id once in buildSrc and reference it from the
// module build script.
object Constants {
    const val APP_ID = "com.example.constapp"
}
