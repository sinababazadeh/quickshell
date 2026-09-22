// =============================================================================
//  NOTIFICATIONSTATE.QML — global notifications store & daemon service
// =============================================================================
//  WHAT THIS IS
//  ------------
//  A singleton that receives notifications from Quickshell.Services.Notifications
//  (the freedesktop Desktop Notifications Specification), groups them by
//  application, and manages unattended alerts for the Hub.
//
//  FEATURES
//  --------
//  • Application Grouping: Repeated notifications from the same app (e.g. kitty)
//    are bundled into a single item with an alert count badge (e.g. ×10).
//  • Dynamic Banner Dispatch: Broadcasts notificationReceived signal to trigger
//    the Dynamic Island banner morph on the bar.
//  • Full Persistence & History: Stores latest summary/body, timestamps, and
//    allows clearing individual app groups or clearing all.
// =============================================================================
pragma Singleton
import Quickshell
import Quickshell.Services.Notifications
import QtQuick

Item {
    id: root

    // Grouped notifications: array of objects
    // [
    //   {
    //     appName: "kitty",
    //     appIcon: "terminal",
    //     count: 10,
    //     latestSummary: "build finished in 4s",
    //     latestBody: "All 42 tests passed",
    //     latestTime: "14:32",
    //     items: [ ... ],
    //     expanded: false
    //   }
    // ]
    property var groups: []

    // Total unattended notifications count across all groups
    property int totalCount: 0

    // Latest notification received (raw)
    property var latestNotification: null

    // Signal emitted whenever a notification arrives
    signal notificationReceived(var notif)

    // ─── Native Quickshell Notification Server ───────────────────────────────────
    NotificationServer {
        id: server
        actionsSupported: true
        bodySupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: notification => {
            if (notification.tracked !== undefined) {
                notification.tracked = true
            }

            let appName = (notification.appName && notification.appName.trim() !== "")
                ? notification.appName
                : "System"

            let appIcon = notification.appIcon || ""
            let summary = notification.summary || ""
            let body = notification.body || ""
            let now = new Date()
            let timeStr = Qt.formatDateTime(now, "hh:mm")

            root.receiveNotification({
                id: notification.id || Date.now(),
                appName: appName,
                appIcon: appIcon,
                summary: summary,
                body: body,
                time: timeStr,
                timestamp: Date.now()
            })
        }
    }

    // ─── Resolve App Icon to Material Symbol Glyph ──────────────────────────────
    function resolveIcon(appName, appIcon) {
        let app = (appName || "").toLowerCase()
        let ico = (appIcon || "").toLowerCase()

        // Terminal emulators
        if (ico.includes("terminal") || app.includes("kitty") || app.includes("alacritty")
            || app.includes("foot") || app.includes("wezterm") || app.includes("konsole")
            || app.includes("bash") || app.includes("zsh")) {
            return "terminal"
        }

        // Music & Media
        if (ico.includes("music") || ico.includes("spotify") || app.includes("spotify")
            || app.includes("clementine") || app.includes("rhythmbox") || app.includes("mpd")
            || app.includes("vlc") || app.includes("media")) {
            return "music_note"
        }

        // Browsers & Web
        if (app.includes("firefox") || app.includes("chrome") || app.includes("chromium")
            || app.includes("brave") || app.includes("zen") || app.includes("browser")
            || ico.includes("web") || ico.includes("browser")) {
            return "travel_explore"
        }

        // Chat & Communication
        if (app.includes("discord") || app.includes("slack") || app.includes("telegram")
            || app.includes("whatsapp") || app.includes("signal") || app.includes("element")
            || app.includes("matrix") || app.includes("chat") || ico.includes("chat")
            || ico.includes("im-")) {
            return "chat"
        }

        // Email
        if (app.includes("thunderbird") || app.includes("mail") || app.includes("email")
            || app.includes("geary") || app.includes("kmail") || ico.includes("mail")) {
            return "mail"
        }

        // Code editors & IDEs
        if (app.includes("code") || app.includes("vsc") || app.includes("neovim")
            || app.includes("nvim") || app.includes("intellij") || app.includes("sublime")) {
            return "code"
        }

        // Downloads
        if (app.includes("download") || ico.includes("download") || app.includes("aria")
            || app.includes("torrent")) {
            return "download"
        }

        // Errors & Alerts
        if (app.includes("error") || ico.includes("error") || ico.includes("dialog-error")) {
            return "error"
        }
        if (app.includes("warn") || ico.includes("warn") || ico.includes("dialog-warning")) {
            return "warning"
        }

        // Package management / system updates
        if (app.includes("pacman") || app.includes("yay") || app.includes("paru")
            || app.includes("upgrade") || app.includes("update") || app.includes("system")) {
            return "system_update"
        }

        // Direct material symbol if given
        if (ico.length > 0 && !ico.includes("/") && !ico.includes(".")) {
            return ico
        }

        return "notifications"
    }

    // ─── Process Incoming Notification ──────────────────────────────────────────
    function receiveNotification(notif) {
        let appKey = (notif.appName || "System").trim()
        let resolvedGlyph = resolveIcon(appKey, notif.appIcon)
        let list = (root.groups || []).slice()
        let foundIdx = -1

        for (let i = 0; i < list.length; i++) {
            if (list[i].appName.toLowerCase() === appKey.toLowerCase()) {
                foundIdx = i
                break
            }
        }

        if (foundIdx >= 0) {
            // Existing app: increment count and prepend to item history
            let existing = list[foundIdx]
            let updatedItems = (existing.items || []).slice()
            updatedItems.unshift(notif)

            let updatedGroup = {
                appName: existing.appName,
                appIcon: existing.appIcon || resolvedGlyph,
                count: (existing.count || 1) + 1,
                latestSummary: notif.summary || existing.latestSummary,
                latestBody: notif.body || existing.latestBody,
                latestTime: notif.time,
                items: updatedItems,
                expanded: existing.expanded || false
            }

            // Move this app's group to the top
            list.splice(foundIdx, 1)
            list.unshift(updatedGroup)
        } else {
            // New app group
            let newGroup = {
                appName: appKey,
                appIcon: resolvedGlyph,
                count: 1,
                latestSummary: notif.summary,
                latestBody: notif.body,
                latestTime: notif.time,
                items: [notif],
                expanded: false
            }
            list.unshift(newGroup)
        }

        root.groups = list

        // Update totalCount
        let sum = 0
        for (let i = 0; i < list.length; i++) {
            sum += (list[i].count || 1)
        }
        root.totalCount = sum
        root.latestNotification = notif

        // Dispatch signal for bar Dynamic Island morph
        root.notificationReceived(notif)
    }

    // ─── Query Group by App Name ────────────────────────────────────────────────
    function getGroup(appName) {
        if (!appName) return null
        let key = appName.toLowerCase().trim()
        for (let i = 0; i < root.groups.length; i++) {
            if (root.groups[i].appName.toLowerCase() === key) {
                return root.groups[i]
            }
        }
        return null
    }

    // ─── Toggle Group Expansion (Accordion) ─────────────────────────────────────
    function toggleGroupExpanded(appName) {
        if (!appName) return
        let list = (root.groups || []).slice()
        let key = appName.toLowerCase().trim()
        for (let i = 0; i < list.length; i++) {
            if (list[i].appName.toLowerCase() === key) {
                let g = list[i]
                list[i] = {
                    appName: g.appName,
                    appIcon: g.appIcon,
                    count: g.count,
                    latestSummary: g.latestSummary,
                    latestBody: g.latestBody,
                    latestTime: g.latestTime,
                    items: g.items,
                    expanded: !g.expanded
                }
                break
            }
        }
        root.groups = list
    }

    // ─── Clear All Notifications for an App Group ───────────────────────────────
    function clearGroup(appName) {
        if (!appName) return
        let list = (root.groups || []).slice()
        let key = appName.toLowerCase().trim()
        let filtered = list.filter(g => g.appName.toLowerCase() !== key)
        root.groups = filtered

        let sum = 0
        for (let i = 0; i < filtered.length; i++) {
            sum += (filtered[i].count || 1)
        }
        root.totalCount = sum
    }

    // ─── Clear All Notifications ────────────────────────────────────────────────
    function clearAll() {
        root.groups = []
        root.totalCount = 0
    }

    // ─── Test Helper ────────────────────────────────────────────────────────────
    function sendTestNotification(appName, summary, body) {
        let app = appName || "kitty"
        let sum = summary || "Command completed"
        let bod = body || "Build passed with 0 errors"
        let now = new Date()

        receiveNotification({
            id: Date.now(),
            appName: app,
            appIcon: "",
            summary: sum,
            body: bod,
            time: Qt.formatDateTime(now, "hh:mm"),
            timestamp: Date.now()
        })
    }
}
