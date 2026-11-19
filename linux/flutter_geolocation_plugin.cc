#include "include/flutter_geolocation/flutter_geolocation_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#include <gtk/gtk.h>

#include <cstring>

#define FLUTTER_GEOLOCATION_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), flutter_geolocation_plugin_get_type(), \
                              FlutterGeolocationPlugin))

struct _FlutterGeolocationPlugin {
  GObject parent_instance;
  FlMethodChannel* method_channel;
  FlEventChannel* position_channel;
  FlEventChannel* service_channel;
  GDBusConnection* system_bus;
  guint location_signal_id;
  gchar* active_client_path;
};

G_DEFINE_TYPE(FlutterGeolocationPlugin, flutter_geolocation_plugin,
              g_object_get_type())

static double read_dbus_double(GDBusConnection* bus,
                               const gchar* object_path,
                               const gchar* prop_name,
                               double fallback) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) res = g_dbus_connection_call_sync(
      bus, "org.freedesktop.GeoClue2", object_path,
      "org.freedesktop.DBus.Properties", "Get",
      g_variant_new("(ss)", "org.freedesktop.GeoClue2.Location", prop_name),
      G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 3000, nullptr, &error);
  if (!res) return fallback;
  g_autoptr(GVariant) inner = nullptr;
  g_variant_get(res, "(v)", &inner);
  if (inner && g_variant_is_of_type(inner, G_VARIANT_TYPE_DOUBLE)) {
    return g_variant_get_double(inner);
  }
  return fallback;
}

static FlValue* location_object_to_fl_value(GDBusConnection* bus,
                                            const gchar* location_path) {
  double lat = read_dbus_double(bus, location_path, "Latitude", 0.0);
  double lon = read_dbus_double(bus, location_path, "Longitude", 0.0);
  double acc = read_dbus_double(bus, location_path, "Accuracy", 0.0);
  double alt = read_dbus_double(bus, location_path, "Altitude", 0.0);
  double speed = read_dbus_double(bus, location_path, "Speed", 0.0);
  double heading = read_dbus_double(bus, location_path, "Heading", 0.0);
  gint64 now_ms = g_get_real_time() / 1000;

  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "latitude", fl_value_new_float(lat));
  fl_value_set_string_take(map, "longitude", fl_value_new_float(lon));
  fl_value_set_string_take(map, "timestamp", fl_value_new_int(now_ms));
  fl_value_set_string_take(map, "accuracy", fl_value_new_float(acc));
  fl_value_set_string_take(map, "altitude", fl_value_new_float(alt));
  fl_value_set_string_take(map, "altitudeAccuracy", fl_value_new_float(0.0));
  fl_value_set_string_take(map, "heading", fl_value_new_float(heading >= 0 ? heading : 0.0));
  fl_value_set_string_take(map, "headingAccuracy", fl_value_new_float(0.0));
  fl_value_set_string_take(map, "speed", fl_value_new_float(speed >= 0 ? speed : 0.0));
  fl_value_set_string_take(map, "speedAccuracy", fl_value_new_float(0.0));
  fl_value_set_string_take(map, "isMocked", fl_value_new_bool(FALSE));
  fl_value_set_string_take(map, "provider", fl_value_new_string("geoclue"));
  return map;
}

static gboolean is_geoclue_available(FlutterGeolocationPlugin* self) {
  if (!self->system_bus) {
    self->system_bus = g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, nullptr);
  }
  if (!self->system_bus) return FALSE;
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) res = g_dbus_connection_call_sync(
      self->system_bus, "org.freedesktop.GeoClue2",
      "/org/freedesktop/GeoClue2/Manager", "org.freedesktop.DBus.Properties",
      "Get",
      g_variant_new("(ss)", "org.freedesktop.GeoClue2.Manager", "InUse"),
      G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, &error);
  return res != nullptr;
}

static gchar* create_geoclue_client(GDBusConnection* bus) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) res = g_dbus_connection_call_sync(
      bus, "org.freedesktop.GeoClue2", "/org/freedesktop/GeoClue2/Manager",
      "org.freedesktop.GeoClue2.Manager", "GetClient", nullptr,
      G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, 3000, nullptr, &error);
  if (!res) return nullptr;
  gchar* path = nullptr;
  g_variant_get(res, "(o)", &path);
  if (path) {
    g_dbus_connection_call_sync(
        bus, "org.freedesktop.GeoClue2", path,
        "org.freedesktop.DBus.Properties", "Set",
        g_variant_new("(ssv)", "org.freedesktop.GeoClue2.Client", "DesktopId",
                      g_variant_new_string("flutter_geolocation")),
        nullptr, G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, nullptr);
  }
  return path;
}

static void on_geoclue_location_updated(GDBusConnection* connection,
                                        const gchar* sender_name,
                                        const gchar* object_path,
                                        const gchar* interface_name,
                                        const gchar* signal_name,
                                        GVariant* parameters,
                                        gpointer user_data) {
  auto* self = FLUTTER_GEOLOCATION_PLUGIN(user_data);
  const gchar* old_loc = nullptr;
  const gchar* new_loc = nullptr;
  g_variant_get(parameters, "(&o&o)", &old_loc, &new_loc);
  if (new_loc && self->position_channel) {
    g_autoptr(FlValue) map = location_object_to_fl_value(connection, new_loc);
    fl_event_channel_send(self->position_channel, map, nullptr, nullptr);
  }
}

static FlMethodErrorResponse* on_position_listen(FlEventChannel* channel,
                                                 FlValue* args,
                                                 gpointer user_data) {
  auto* self = FLUTTER_GEOLOCATION_PLUGIN(user_data);
  if (!is_geoclue_available(self)) {
    return fl_method_error_response_new(
        "SERVICE_DISABLED", "GeoClue2 location daemon is unavailable.", nullptr);
  }
  self->active_client_path = create_geoclue_client(self->system_bus);
  if (!self->active_client_path) {
    return fl_method_error_response_new(
        "SERVICE_DISABLED", "Failed to create GeoClue2 client.", nullptr);
  }
  self->location_signal_id = g_dbus_connection_signal_subscribe(
      self->system_bus, "org.freedesktop.GeoClue2",
      "org.freedesktop.GeoClue2.Client", "LocationUpdated",
      self->active_client_path, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      on_geoclue_location_updated, self, nullptr);

  g_dbus_connection_call_sync(
      self->system_bus, "org.freedesktop.GeoClue2", self->active_client_path,
      "org.freedesktop.GeoClue2.Client", "Start", nullptr, nullptr,
      G_DBUS_CALL_FLAGS_NONE, 3000, nullptr, nullptr);
  return nullptr;
}

static FlMethodErrorResponse* on_position_cancel(FlEventChannel* channel,
                                                 FlValue* args,
                                                 gpointer user_data) {
  auto* self = FLUTTER_GEOLOCATION_PLUGIN(user_data);
  if (self->system_bus && self->location_signal_id != 0) {
    g_dbus_connection_signal_unsubscribe(self->system_bus,
                                         self->location_signal_id);
    self->location_signal_id = 0;
  }
  if (self->system_bus && self->active_client_path) {
    g_dbus_connection_call_sync(
        self->system_bus, "org.freedesktop.GeoClue2", self->active_client_path,
        "org.freedesktop.GeoClue2.Client", "Stop", nullptr, nullptr,
        G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, nullptr);
    g_clear_pointer(&self->active_client_path, g_free);
  }
  return nullptr;
}

static FlMethodErrorResponse* on_service_listen(FlEventChannel* channel,
                                                FlValue* args,
                                                gpointer user_data) {
  auto* self = FLUTTER_GEOLOCATION_PLUGIN(user_data);
  gboolean available = is_geoclue_available(self);
  g_autoptr(FlValue) val =
      fl_value_new_string(available ? "enabled" : "disabled");
  fl_event_channel_send(channel, val, nullptr, nullptr);
  return nullptr;
}

static void flutter_geolocation_plugin_handle_method_call(
    FlutterGeolocationPlugin* self, FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "isLocationServiceEnabled") == 0) {
    g_autoptr(FlValue) res = fl_value_new_bool(is_geoclue_available(self));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(res));
  } else if (strcmp(method, "checkPermission") == 0 ||
             strcmp(method, "requestPermission") == 0) {
    gboolean avail = is_geoclue_available(self);
    g_autoptr(FlValue) res =
        fl_value_new_string(avail ? "whileInUse" : "deniedForever");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(res));
  } else if (strcmp(method, "getCurrentPosition") == 0) {
    if (!is_geoclue_available(self)) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "SERVICE_DISABLED", "GeoClue2 location daemon is unavailable.",
          nullptr));
    } else {
      g_autofree gchar* client_path = create_geoclue_client(self->system_bus);
      if (!client_path) {
        response = FL_METHOD_RESPONSE(fl_method_error_response_new(
            "SERVICE_DISABLED", "Failed to create GeoClue2 client.", nullptr));
      } else {
        g_dbus_connection_call_sync(
            self->system_bus, "org.freedesktop.GeoClue2", client_path,
            "org.freedesktop.GeoClue2.Client", "Start", nullptr, nullptr,
            G_DBUS_CALL_FLAGS_NONE, 3000, nullptr, nullptr);
        g_autoptr(GError) err = nullptr;
        g_autoptr(GVariant) prop = g_dbus_connection_call_sync(
            self->system_bus, "org.freedesktop.GeoClue2", client_path,
            "org.freedesktop.DBus.Properties", "Get",
            g_variant_new("(ss)", "org.freedesktop.GeoClue2.Client", "Location"),
            G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 3000, nullptr, &err);
        const gchar* loc_path = nullptr;
        if (prop) {
          g_autoptr(GVariant) inner = nullptr;
          g_variant_get(prop, "(v)", &inner);
          if (inner) loc_path = g_variant_get_string(inner, nullptr);
        }
        if (loc_path && strcmp(loc_path, "/") != 0) {
          g_autoptr(FlValue) map =
              location_object_to_fl_value(self->system_bus, loc_path);
          response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
        } else {
          response = FL_METHOD_RESPONSE(fl_method_error_response_new(
              "TIMEOUT", "No GeoClue2 location fix available yet.", nullptr));
        }
        g_dbus_connection_call_sync(
            self->system_bus, "org.freedesktop.GeoClue2", client_path,
            "org.freedesktop.GeoClue2.Client", "Stop", nullptr, nullptr,
            G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, nullptr);
      }
    }
  } else if (strcmp(method, "getLastKnownPosition") == 0) {
    g_autoptr(FlValue) res = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(res));
  } else if (strcmp(method, "openAppSettings") == 0 ||
             strcmp(method, "openLocationSettings") == 0) {
    g_autoptr(FlValue) res = fl_value_new_bool(FALSE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(res));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void flutter_geolocation_plugin_dispose(GObject* object) {
  auto* self = FLUTTER_GEOLOCATION_PLUGIN(object);
  on_position_cancel(nullptr, nullptr, self);
  g_clear_object(&self->method_channel);
  g_clear_object(&self->position_channel);
  g_clear_object(&self->service_channel);
  g_clear_object(&self->system_bus);
  G_OBJECT_CLASS(flutter_geolocation_plugin_parent_class)->dispose(object);
}

static void flutter_geolocation_plugin_class_init(
    FlutterGeolocationPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = flutter_geolocation_plugin_dispose;
}

static void flutter_geolocation_plugin_init(FlutterGeolocationPlugin* self) {
  self->system_bus = nullptr;
  self->location_signal_id = 0;
  self->active_client_path = nullptr;
}

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  flutter_geolocation_plugin_handle_method_call(
      FLUTTER_GEOLOCATION_PLUGIN(user_data), method_call);
}

void flutter_geolocation_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  FlutterGeolocationPlugin* plugin = FLUTTER_GEOLOCATION_PLUGIN(
      g_object_new(flutter_geolocation_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->method_channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "id.humanize.flutter_geolocation/methods", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      plugin->method_channel, method_call_cb, g_object_ref(plugin),
      g_object_unref);

  plugin->position_channel = fl_event_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "id.humanize.flutter_geolocation/positions", FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(
      plugin->position_channel, on_position_listen, on_position_cancel,
      g_object_ref(plugin), g_object_unref);

  plugin->service_channel = fl_event_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "id.humanize.flutter_geolocation/service_status", FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(
      plugin->service_channel, on_service_listen, nullptr, g_object_ref(plugin),
      g_object_unref);

  g_object_unref(plugin);
}
