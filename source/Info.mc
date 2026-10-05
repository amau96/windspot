import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Ligne d'infos sous la date. Montres avec complications (API 4.2+, compilees avec l'annotation cfg) :
// deux emplacements choisis dans l'editeur de cadran natif (batterie et pas par defaut).
// Autres montres (nocfg) : batterie et pas.

(:nocfg)
function infoTexts() as Array<String> {
    var out = [System.getSystemStats().battery.toNumber().toString() + " %"];
    var steps = ActivityMonitor.getInfo().steps;
    if (steps != null) { out.add(steps.toString() + " pas"); }
    return out;
}

(:nocfg)
function subscribeInfos() as Void {}

(:nocfg)
function dateSlotText() as String? { return null; }

(:nocfg)
function editDelegate() as WatchUi.WatchFaceDelegate? { return null; }
