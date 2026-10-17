import Toybox.Activity;
import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.WatchUi;

// Menu de choix du spot sur la montre (reglages du cadran) :
// Recents / Pres de moi / Facade > Departement > (Secteur) > Spot.
// Les listes de spots sont des ressources JSON (une par departement), chargees a l'ouverture.

const MAX_RECENT = 3;
const NEAR_COUNT = 10;

// Entree de menu : [libelle, sous-libelle, type, donnees]
enum {
    ENTRY_SPOT,     // donnees : [nom, lat, lon, numero]
    ENTRY_LIST,     // donnees : liste d'elements JSON (spots ou secteurs)
    ENTRY_GROUP,    // donnees : numero de ressource du departement
    ENTRY_FACADE,   // donnees : [[departement, numero], ...]
    ENTRY_RECENT,   // donnees : liste de spots recents
    ENTRY_NEAR,     // donnees : position [lat, lon]
    ENTRY_DATA      // menu « Donnees affichees » (montres sans editeur natif)
}

function rootSpotMenu() as [WatchUi.Views, WatchUi.InputDelegates] {
    var entries = [];
    var data = dataMenuEntry();
    if (data != null) { entries.add(data); }
    var recent = Application.Storage.getValue("recent");
    if (recent instanceof Array && recent.size() > 0) {
        entries.add(["Récents", recentNames(recent), ENTRY_RECENT, recent]);
    }
    var here = lastPosition();
    if (here != null) {
        entries.add(["Près de moi", "10 spots les plus proches", ENTRY_NEAR, here]);
    }
    var index = WatchUi.loadResource(Rez.JsonData.SpotIndex) as Array;
    for (var i = 0; i < index.size(); i++) {
        var f = index[i] as Array;
        entries.add([f[0], (f[1] as Array).size().toString() + " zones", ENTRY_FACADE, f[1]]);
    }
    var cur = Application.Properties.getValue("curName");
    return spotMenu("Spot : " + (cur == null ? "?" : cur.toString()), entries, 1);
}

function recentNames(recent as Array) as String {
    var s = "";
    for (var i = 0; i < recent.size(); i++) {
        s += (i > 0 ? ", " : "") + ((recent[i] as Array)[0] as String);
    }
    return s;
}

// Derniere position connue (derniere activite ou dernier fix), sans allumer le GPS
function lastPosition() as Array? {
    var info = Activity.getActivityInfo();
    if (info == null || info.currentLocation == null) {
        return null;
    }
    var d = (info.currentLocation as Position.Location).toDegrees();
    if (d[0] == 0.0 && d[1] == 0.0) {
        return null;
    }
    return d;
}

function spotMenu(title as String, entries as Array, depth as Number) as [WatchUi.Views, WatchUi.InputDelegates] {
    var menu = new WatchUi.Menu2({ :title => title });
    for (var i = 0; i < entries.size(); i++) {
        var e = entries[i] as Array;
        menu.addItem(new WatchUi.MenuItem(e[0] as String, e[1] as String?, i, {}));
    }
    return [menu, new SpotMenuDelegate(entries, depth)];
}

// Libelle d'un spot : les noms longs sont coupes en titre / sous-titre sur « - » ou « , »
function spotLabels(name as String) as Array {
    if (name.length() <= 18) {
        return [name, null];
    }
    var sep = name.find(" - ");
    var len = 3;
    if (sep == null) {
        sep = name.find(", ");
        len = 2;
    }
    if (sep == null) {
        return [name, null];
    }
    return [name.substring(0, sep), name.substring(sep + len, name.length())];
}

// Elements JSON d'un departement ou d'un secteur -> entrees de menu
function listEntries(items as Array) as Array {
    var entries = [];
    for (var i = 0; i < items.size(); i++) {
        var it = items[i] as Array;
        if (it[1] instanceof Array) {
            entries.add([it[0], (it[1] as Array).size().toString() + " spots", ENTRY_LIST, it[1]]);
        } else {
            var l = spotLabels(it[0] as String);
            entries.add([l[0], l[1], ENTRY_SPOT, it]);
        }
    }
    return entries;
}

function distanceKm(a as Array, lat as Float, lon as Float) as Float {
    var k = Math.PI / 180.0;
    var x = (lon - (a[1] as Float)) * k * Math.cos(((a[0] as Float) + lat) * k / 2.0);
    var y = (lat - (a[0] as Float)) * k;
    return (Math.sqrt(x * x + y * y) * 6371.0).toFloat();
}

// Les NEAR_COUNT spots les plus proches : un departement charge a la fois (memoire)
function nearEntries(here as Array) as Array {
    var best = [[]];   // best[0] : liste [distance, spot] triee par distance
    for (var n = 0; n < SPOT_GROUP_COUNT; n++) {
        collectNear(WatchUi.loadResource(spotGroupResource(n)) as Array, here, best);
    }
    var entries = [];
    var list = best[0] as Array;
    for (var i = 0; i < list.size(); i++) {
        var b = list[i] as Array;
        var sp = b[1] as Array;
        entries.add([spotLabels(sp[0] as String)[0], (b[0] as Float).format("%.0f") + " km", ENTRY_SPOT, sp]);
    }
    return entries;
}

function collectNear(items as Array, here as Array, best as Array) as Void {
    for (var i = 0; i < items.size(); i++) {
        var it = items[i] as Array;
        if (it[1] instanceof Array) {
            collectNear(it[1] as Array, here, best);
            continue;
        }
        var d = distanceKm(here, (it[1] as Number or Float).toFloat(), (it[2] as Number or Float).toFloat());
        var list = best[0] as Array;
        var pos = list.size();
        while (pos > 0 && ((list[pos - 1] as Array)[0] as Float) > d) {
            pos--;
        }
        if (pos >= NEAR_COUNT) {
            continue;
        }
        var next = list.slice(0, pos);
        next.add([d, it]);
        next.addAll(list.slice(pos, NEAR_COUNT - 1));
        best[0] = next;
    }
}

// Enregistre le spot choisi (numero), efface les donnees de l'ancien spot et relance une prevision
function chooseSpot(sp as Array) as Void {
    var name = sp[0] as String;
    if (name.length() > 22) {
        name = spotLabels(name)[0] as String;
    }
    var id = sp[3] as Number;
    Application.Properties.setValue("spotId", id);
    Application.Storage.setValue("seenId", id);
    setCurrentSpot(id, name, (sp[1] as Number or Float).toFloat(), (sp[2] as Number or Float).toFloat());

    var recent = Application.Storage.getValue("recent");
    var list = [[name, sp[1], sp[2], id]];
    if (recent instanceof Array) {
        for (var i = 0; i < recent.size() && list.size() < MAX_RECENT; i++) {
            var r = recent[i] as Array;
            if (r.size() == 4 && (r[3] as Number) != id) {
                list.add(r);
            }
        }
    }
    Application.Storage.setValue("recent", list);

    (Application.getApp() as WingFaceApp).registerRefresh();
    WatchUi.requestUpdate();
}

class SpotMenuDelegate extends WatchUi.Menu2InputDelegate {
    var entries as Array;
    var depth as Number;

    function initialize(e as Array, d as Number) {
        Menu2InputDelegate.initialize();
        entries = e;
        depth = d;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var e = entries[item.getId() as Number] as Array;
        var kind = e[2];
        var title = e[0] as String;
        var sub = null;
        if (kind == ENTRY_SPOT) {
            chooseSpot(e[3] as Array);
            for (var i = 0; i < depth; i++) {
                WatchUi.popView(WatchUi.SLIDE_RIGHT);
            }
            return;
        } else if (kind == ENTRY_LIST) {
            sub = listEntries(e[3] as Array);
        } else if (kind == ENTRY_GROUP) {
            sub = listEntries(WatchUi.loadResource(spotGroupResource(e[3] as Number)) as Array);
        } else if (kind == ENTRY_FACADE) {
            sub = [];
            var depts = e[3] as Array;
            for (var i = 0; i < depts.size(); i++) {
                var d = depts[i] as Array;
                sub.add([d[0], null, ENTRY_GROUP, d[1]]);
            }
        } else if (kind == ENTRY_RECENT) {
            sub = [];
            var r = e[3] as Array;
            for (var i = 0; i < r.size(); i++) {
                sub.add([(r[i] as Array)[0], null, ENTRY_SPOT, r[i]]);
            }
        } else if (kind == ENTRY_DATA) {
            openDataMenu();
            return;
        } else if (kind == ENTRY_NEAR) {
            sub = nearEntries(e[3] as Array);
        }
        var v = spotMenu(title, sub, depth + 1);
        WatchUi.pushView(v[0], v[1], WatchUi.SLIDE_LEFT);
    }
}
