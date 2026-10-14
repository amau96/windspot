import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Complications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Emplacements 1 et 2 de l'editeur natif ; defaut : batterie, pas
(:cfg)
function infoIds() as Array<Complications.Id> {
    var ids = [new Complications.Id(Complications.COMPLICATION_TYPE_BATTERY),
               new Complications.Id(Complications.COMPLICATION_TYPE_STEPS)];
    if (Application has :WatchFaceConfig) {
        var st = Application.WatchFaceConfig.getSettings(null);
        if (st != null && st.complicationSettings != null) {
            var cs = st.complicationSettings;
            for (var i = 0; i < cs.size(); i++) {
                var slot = cs[i].uniqueIdentifier;
                var cid = cs[i].complicationId;
                if (cid != null && slot != null && slot >= 1 && slot <= 2) {
                    ids[slot - 1] = cid;
                }
            }
        }
    }
    return ids;
}

// Emplacement 3 (a la place de la date) : null si rien n'est choisi -> notre date
(:cfg)
function dateSlotId() as Complications.Id? {
    if (Application has :WatchFaceConfig) {
        var st = Application.WatchFaceConfig.getSettings(null);
        if (st != null && st.complicationSettings != null) {
            var cs = st.complicationSettings;
            for (var i = 0; i < cs.size(); i++) {
                if (cs[i].uniqueIdentifier == 3) { return cs[i].complicationId; }
            }
        }
    }
    return null;
}

(:cfg)
function dateSlotText() as String? {
    var id = dateSlotId();
    return (id == null) ? null : infoText(id);
}

(:cfg)
function subscribeInfos() as Void {
    var ids = infoIds();
    var d = dateSlotId();
    if (d != null) { ids.add(d); }
    for (var i = 0; i < ids.size(); i++) {
        try { Complications.subscribeToUpdates(ids[i]); } catch (e) { }
    }
}

(:cfg)
function infoTexts() as Array<String> {
    var ids = infoIds();
    var out = [];
    for (var i = 0; i < ids.size(); i++) {
        var t = infoText(ids[i]);
        if (t != null && !t.equals("")) { out.add(t); }
    }
    return out;
}

// Valeur lisible d'une complication : unites courantes en francais, sinon valeur + unite/libelle
(:cfg)
function infoText(id as Complications.Id) as String? {
    var c = null;
    try { c = Complications.getComplication(id); } catch (e) { return null; }
    if (c == null || c.value == null) { return null; }
    var v = c.value;
    var type = id.getType();
    if (type == Complications.COMPLICATION_TYPE_BATTERY) { return v.format("%d") + " %"; }
    if (type == Complications.COMPLICATION_TYPE_STEPS) {
        // certaines montres donnent les pas en milliers (Float 1.4 -> « 1.400000 ») : compteur exact de la montre
        var steps = ActivityMonitor.getInfo().steps;
        if (steps == null) { steps = (v instanceof Lang.Float || v instanceof Lang.Double) ? (v * 1000).toNumber() : v; }
        return steps.toString() + " pas";
    }
    if (type == Complications.COMPLICATION_TYPE_HEART_RATE) { return v.format("%d") + " bpm"; }
    if (type == Complications.COMPLICATION_TYPE_BODY_BATTERY) { return "BB " + v.format("%d"); }
    if (type == Complications.COMPLICATION_TYPE_SUNRISE || type == Complications.COMPLICATION_TYPE_SUNSET) {
        if (v instanceof Lang.Number) {
            var m = (v > 1440) ? v / 60 : v;          // secondes ou minutes depuis minuit
            return (type == Complications.COMPLICATION_TYPE_SUNSET ? "☾ " : "☀ ") + (m / 60).format("%d") + ":" + (m % 60).format("%02d");
        }
    }
    var txt = (v instanceof Lang.Float || v instanceof Lang.Double) ? v.format("%.1f") : v.toString();
    if (c.unit instanceof Lang.String) { return txt + " " + c.unit; }
    if (c.shortLabel instanceof Lang.String) { return c.shortLabel + " " + txt; }
    return txt;
}

// Delegue du mode edition : redessine quand l'utilisateur change un emplacement
(:cfg)
class EditDelegate extends WatchUi.WatchFaceDelegate {
    function initialize() {
        WatchFaceDelegate.initialize();
    }

    function onWatchFaceConfigEdited(options) {
        subscribeInfos();
        WatchUi.requestUpdate();
    }
}

(:cfg)
function editDelegate() as WatchUi.WatchFaceDelegate? { return new EditDelegate(); }
