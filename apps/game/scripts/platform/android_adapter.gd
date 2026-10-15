class_name LFAndroidAdapter
extends LFNativeAdapter
## Android: the "LoopFactoryShare" Godot plugin (android/share-plugin, enabled through
## addons/loopfactory_share in Gradle builds). Behaviour is unchanged from the Android beta build:
## share() opens the system chooser through a FileProvider URI and consumeLaunchUri() returns the
## App Link the activity was opened with. Android has no secure-storage backend here, so the refresh
## token stays in the save file exactly as before.

const SINGLETON := "LoopFactoryShare"


func platform_name() -> String:
	return "android"
