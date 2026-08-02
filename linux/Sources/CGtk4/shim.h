#ifndef CODEXBAR_CGTK4_SHIM_H
#define CODEXBAR_CGTK4_SHIM_H

#include <gtk/gtk.h>

static inline gboolean codexbar_send_desktop_notification(
    const gchar *summary,
    const gchar *body,
    guint8 urgency,
    gboolean suppress_sound
) {
    GError *error = NULL;
    GDBusConnection *connection = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (connection == NULL) {
        g_clear_error(&error);
        return FALSE;
    }

    GVariantBuilder hints;
    g_variant_builder_init(&hints, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&hints, "{sv}", "transient", g_variant_new_boolean(TRUE));
    g_variant_builder_add(&hints, "{sv}", "urgency", g_variant_new_byte(urgency));
    g_variant_builder_add(&hints, "{sv}", "suppress-sound", g_variant_new_boolean(suppress_sound));

    GVariant *reply = g_dbus_connection_call_sync(
        connection,
        "org.freedesktop.Notifications",
        "/org/freedesktop/Notifications",
        "org.freedesktop.Notifications",
        "Notify",
        g_variant_new(
            "(susss@as@a{sv}i)",
            "CodexBar",
            0u,
            "",
            summary,
            body,
            g_variant_new_strv(NULL, 0),
            g_variant_builder_end(&hints),
            8000),
        NULL,
        G_DBUS_CALL_FLAGS_NONE,
        8000,
        NULL,
        &error);
    g_object_unref(connection);
    if (reply == NULL) {
        g_clear_error(&error);
        return FALSE;
    }
    g_variant_unref(reply);
    return TRUE;
}

#endif
