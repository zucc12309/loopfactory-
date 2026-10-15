// GDExtension entry point: registers LoopFactoryIOS and exposes one instance as the Engine
// singleton "LoopFactoryIOS" (looked up by apps/game/scripts/platform/platform_services.gd).
#include "loopfactory_ios.h"

#include <gdextension_interface.h>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

static LoopFactoryIOS *lf_instance = nullptr;

static void initialize_loopfactory_native(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(LoopFactoryIOS);
	lf_instance = memnew(LoopFactoryIOS);
	Engine::get_singleton()->register_singleton("LoopFactoryIOS", lf_instance);
}

static void uninitialize_loopfactory_native(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	Engine::get_singleton()->unregister_singleton("LoopFactoryIOS");
	memdelete(lf_instance);
	lf_instance = nullptr;
}

extern "C" {
GDExtensionBool GDE_EXPORT loopfactory_native_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_loopfactory_native);
	init_obj.register_terminator(uninitialize_loopfactory_native);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
