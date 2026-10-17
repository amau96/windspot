import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Ligne d'infos sous la date. Montres avec complications (API 4.2+, compilees avec l'annotation cfg) :
// trois emplacements choisis dans l'editeur de cadran natif (voir InfoCfg.mc).
// Autres montres (nocfg) : trois emplacements choisis dans le menu de reglages de la montre
// (« Donnees affichees »), la montre lisant elle-meme chaque donnee. Proprietes data1 / data2
// (ligne du haut, batterie et pas par defaut) et data3 (a la place de la date, la date par defaut).

// Codes des donnees (proprietes data1 a data3)
enum {
    DATA_NONE, DATA_BATTERY, DATA_STEPS, DATA_HEART, DATA_CALORIES, DATA_FLOORS,
    DATA_DISTANCE, DATA_NOTIFS, DATA_SUNRISE, DATA_SUNSET, DATA_DATE
}

(:nocfg)
const DATA_NAMES = ["Rien", "Batterie", "Pas", "Cardio", "Calories", "Étages", "Distance du jour",
    "Notifications", "Lever du soleil", "Coucher du soleil", "Date"];

(:nocfg)
function infoTexts() as Array<String> {
    var out = [];
    for (var s = 1; s <= 2; s++) {
        var t = dataText(dataSlot(s));
        if (t != null && !t.equals("")) { out.add(t); }
    }
    return out;
}

(:nocfg)
function subscribeInfos() as Void {}

// Emplacement 3 : null -> notre date ; « Rien » -> espace (rien d'affiche)
(:nocfg)
function dateSlotText() as String? {
    var k = dataSlot(3);
    if (k == DATA_DATE) { return null; }
    var t = dataText(k);
    return (t == null || t.equals("")) ? " " : t;
}

(:nocfg)
function editDelegate() as WatchUi.WatchFaceDelegate? { return null; }

(:nocfg)
function dataSlot(s as Number) as Number {
    var v = Application.Properties.getValue("data" + s);
    if (v == null) { v = [DATA_BATTERY, DATA_STEPS, DATA_DATE][s - 1]; }
    return v as Number;
}

// La montre sait-elle fournir cette donnee ? (les listes du menu ne proposent que celles-la)
(:nocfg)
function dataAvailable(k as Number) as Boolean {
    if (k == DATA_HEART) { return (ActivityMonitor has :getHeartRateHistory); }
    if (k == DATA_FLOORS) { return (ActivityMonitor.getInfo() has :floorsClimbed); }
    if (k == DATA_NOTIFS) { return (System.getDeviceSettings() has :notificationCount); }
    return true;
}

// Texte affiche ; null si la donnee n'est pas disponible en ce moment
(:nocfg)
function dataText(k as Number) as String? {
    if (k == DATA_NONE || k == DATA_DATE || !dataAvailable(k)) { return null; }
    if (k == DATA_BATTERY) { return System.getSystemStats().battery.toNumber().toString() + " %"; }
    if (k == DATA_SUNRISE || k == DATA_SUNSET) {
        var c = spotCoords();
        var t = Gregorian.info(new Time.Moment(sunTime(c[0], c[1], Time.now().value(), k == DATA_SUNRISE)), Time.FORMAT_SHORT);
        return (k == DATA_SUNRISE ? "lever " : "coucher ") + t.hour.toString() + ":" + t.min.format("%02d");
    }
    if (k == DATA_NOTIFS) { return System.getDeviceSettings().notificationCount.toString() + " notif."; }
    if (k == DATA_HEART) {
        var hr = Activity.getActivityInfo() != null ? Activity.getActivityInfo().currentHeartRate : null;
        if (hr == null) {
            var it = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (it != null && it.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) { hr = it.heartRate; }
        }
        return (hr == null) ? null : hr.toString() + " bpm";
    }
    var info = ActivityMonitor.getInfo();
    if (k == DATA_STEPS) { return (info.steps == null) ? null : info.steps.toString() + " pas"; }
    if (k == DATA_CALORIES) { return (info.calories == null) ? null : info.calories.toString() + " kcal"; }
    if (k == DATA_FLOORS) { return (info.floorsClimbed == null) ? null : info.floorsClimbed.toString() + " étages"; }
    if (k == DATA_DISTANCE) {
        if (info.distance == null) { return null; }
        var d = info.distance / 10000;    // cm -> dixiemes de km
        return (d / 10).toString() + "," + (d % 10).toString() + " km";
    }
    return null;
}

// ---------- menu « Donnees affichees » (reglages sur la montre) ----------

// Entree du menu racine des reglages (voir SpotMenu.mc)
(:nocfg)
function dataMenuEntry() as Array? {
    return ["Données affichées", null, ENTRY_DATA, null];
}

// Emplacements visibles : la ligne du haut est masquee sur les petits ecrans sans police vectorielle
(:nocfg)
function openDataMenu() as Void {
    var ds = System.getDeviceSettings();
    var small = ds.screenWidth <= 240 && !(Graphics has :getVectorFont);
    var slots = small ? [3] : [1, 2, 3];
    var menu = new WatchUi.Menu2({ :title => "Données affichées" });
    for (var i = 0; i < slots.size(); i++) {
        var s = slots[i];
        var label = (s == 3) ? "À la place de la date" : "Ligne du haut " + s;
        menu.addItem(new WatchUi.MenuItem(label, DATA_NAMES[dataSlot(s)], s, {}));
    }
    WatchUi.pushView(menu, new DataSlotsDelegate(), WatchUi.SLIDE_LEFT);
}

(:nocfg)
class DataSlotsDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var s = item.getId() as Number;
        var menu = new WatchUi.Menu2({ :title => item.getLabel() });
        var codes = [];
        for (var k = DATA_BATTERY; k <= DATA_SUNSET; k++) {
            if (dataAvailable(k)) { codes.add(k); }
        }
        if (s == 3) { codes = [DATA_DATE].addAll(codes); }
        codes.add(DATA_NONE);
        for (var i = 0; i < codes.size(); i++) {
            var k = codes[i] as Number;
            menu.addItem(new WatchUi.MenuItem(DATA_NAMES[k], (k == dataSlot(s)) ? "actuel" : null, k, {}));
        }
        WatchUi.pushView(menu, new DataChoiceDelegate(s, item), WatchUi.SLIDE_LEFT);
    }
}

(:nocfg)
class DataChoiceDelegate extends WatchUi.Menu2InputDelegate {
    var slot as Number;
    var parent as WatchUi.MenuItem;

    function initialize(s as Number, p as WatchUi.MenuItem) {
        Menu2InputDelegate.initialize();
        slot = s;
        parent = p;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var k = item.getId() as Number;
        Application.Properties.setValue("data" + slot, k);
        parent.setSubLabel(DATA_NAMES[k]);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.requestUpdate();
    }
}
