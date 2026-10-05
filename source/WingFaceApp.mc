import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

(:background)
class WingFaceApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    var editMode = false;

    function onStart(state) {
        editMode = (state != null && state[:launchedFromWatchFaceSettingsEditor] == true);
    }

    function getInitialView() {
        resolveSpot();
        registerRefresh();
        var d = editMode ? editDelegate() : null;
        if (d != null) {
            return [ new WingFaceView(), d ];
        }
        return [ new WingFaceView() ];
    }

    // Reglages sur la montre : choix du spot
    function getSettingsView() {
        return rootSpotMenu();
    }

    function getServiceDelegate() {
        return [ new WingService() ];
    }

    // Appele quand le service d'arriere-plan renvoie ses donnees
    function onBackgroundData(data) {
        if (data instanceof Dictionary) {
            if (data.hasKey("v") && !forCurrentSpot(data)) {
                // reponse pour un ancien spot (spot change pendant la requete) : on redemande
                registerRefresh();
            } else if (data.hasKey("v")) {
                Application.Storage.setValue("wind", data);
                Application.Storage.deleteValue("err");
                registerRefresh();
            } else if (data.hasKey("err")) {
                Application.Storage.setValue("err", data["err"]);
            }
        }
        WatchUi.requestUpdate();
    }

    function onSettingsChanged() {
        resolveSpot();
        registerRefresh();
        WatchUi.requestUpdate();
    }

    // Requete periodique ; si les donnees sont perimees ou ne partent pas de minuit
    // (ancien format), une requete immediate (au plus tot 5 min apres la precedente).
    function registerRefresh() {
        var minutes = Application.Properties.getValue("refreshMin");
        if (minutes == null || minutes < 5) {
            minutes = 60;
        }
        if (needsFetch(minutes)) {
            var at = Time.now();
            var last = Background.getLastTemporalEventTime();
            if (last != null) {
                var earliest = last.add(new Time.Duration(5 * 60));
                if (earliest.greaterThan(at)) { at = earliest; }
            }
            Background.registerForTemporalEvent(at);
        } else {
            Background.registerForTemporalEvent(new Time.Duration(minutes * 60));
        }
    }

    // Spot effectif : liste « Spot » (telephone) ou menu montre (numero spotId).
    // Recopie dans curName/curLat/curLon, lus par le cadran et le service d'arriere-plan.
    function resolveSpot() {
        var id = Application.Properties.getValue("spotId");
        if (id == null) { id = 0; }
        var seenId = Application.Storage.getValue("seenId");
        var cur = Application.Properties.getValue("curId");
        if (id == seenId && cur != null && cur >= 0) { return; }
        Application.Storage.setValue("seenId", id);
        var sp = (id > 0) ? findSpot(id) : null;
        if (sp == null) {
            // spot par defaut de la montre (proprietes spotName/lat/lon)
            sp = [Application.Properties.getValue("spotName"), Application.Properties.getValue("lat"), Application.Properties.getValue("lon"), 0];
        }
        setCurrentSpot(sp[3], sp[0], sp[1], sp[2]);
    }

    // Les donnees recues concernent-elles le spot actuel ? (anciennes versions : pas de coordonnees -> oui)
    function forCurrentSpot(data) {
        if (!data.hasKey("lat")) { return true; }
        var lat = Application.Properties.getValue("curLat");
        var lon = Application.Properties.getValue("curLon");
        if (lat == null || lat.equals("")) { lat = Application.Properties.getValue("lat"); }
        if (lon == null || lon.equals("")) { lon = Application.Properties.getValue("lon"); }
        return lat != null && lon != null && lat.toString().equals(data["lat"]) && lon.toString().equals(data["lon"]);
    }

    function needsFetch(minutes) {
        var d = Application.Storage.getValue("wind");
        if (!(d instanceof Dictionary) || d["f"] == null || d["t0"] == null) {
            return true;
        }
        var now = Time.now().value();
        if (now - d["f"] > minutes * 60) {
            return true;
        }
        return d["t0"] > Time.today().value();
    }
}

// Enregistre le spot effectif et efface les donnees de l'ancien spot
function setCurrentSpot(id, name, lat, lon) {
    Application.Properties.setValue("curId", id);
    Application.Properties.setValue("curName", name == null ? "" : name.toString());
    Application.Properties.setValue("curLat", lat == null ? "" : (lat instanceof Lang.String ? lat : lat.format("%.3f")));
    Application.Properties.setValue("curLon", lon == null ? "" : (lon instanceof Lang.String ? lon : lon.format("%.3f")));
    Application.Storage.deleteValue("wind");
}

// Cherche un spot par son numero dans les listes par departement
function findSpot(id) {
    for (var n = 0; n < SPOT_GROUP_COUNT; n++) {
        var sp = findIn(WatchUi.loadResource(spotGroupResource(n)), id);
        if (sp != null) { return sp; }
    }
    return null;
}

function findIn(items, id) {
    for (var i = 0; i < items.size(); i++) {
        var it = items[i];
        if (it[1] instanceof Lang.Array) {
            var sp = findIn(it[1], id);
            if (sp != null) { return sp; }
        } else if (it[3] == id) {
            return it;
        }
    }
    return null;
}
