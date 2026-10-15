@tool
extends EditorPlugin
## Adds the share plugin AAR to Gradle Android exports when it has been built
## (addons/loopfactory_share/bin/share-plugin-release.aar). Not enabled by default: enable it under
## Project Settings → Plugins after building the AAR (docs/BETA_READINESS_IMPLEMENTATION.md).

var _export: AndroidExportPlugin


func _enter_tree() -> void:
	_export = AndroidExportPlugin.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class AndroidExportPlugin extends EditorExportPlugin:
	const AAR := "res://addons/loopfactory_share/bin/share-plugin-release.aar"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid and FileAccess.file_exists(AAR)

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["loopfactory_share/bin/share-plugin-release.aar"])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["androidx.core:core:1.13.1"])

	func _get_name() -> String:
		return "LoopFactoryShare"
