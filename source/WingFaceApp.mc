import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
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
        resolveModel();
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
        // heure de la derniere reponse du service : sans reponse apres un reveil, le cadran le dit
        Application.Storage.setValue("rx", Time.now().value());
        if (data instanceof Dictionary) {
            if (data.hasKey("ping")) {
                // statistiques envoyees : [jour, version, spot] ; rien de plus avant demain,
                // une nouvelle version ou un autre spot
                var p = data["ping"];
                saveState("pingDay", p[0]);
                saveState("pingVer", p[1]);
                saveState("pingSpot", p[2]);
            }
            if (data.hasKey("errPing")) {
                // fetch_error envoye : [jour, code] ; le meme code n'est pas renvoye avant demain
                saveState("errDay", data["errPing"][0]);
                saveState("errCode", data["errPing"][1]);
            }
            if (data.hasKey("errPend")) {
                // erreur meteo pas encore envoyee (pas de connexion), ou envoyee (texte vide)
                saveState("errPend", data["errPend"]);
            }
            if (data.hasKey("same")) {
                // pas de nouveau run : les donnees restent valables, on note seulement l'heure du controle
                Application.Storage.setValue("chk", Time.now().value());
                Application.Storage.deleteValue("err");
                registerRefresh();
            } else if (data.hasKey("v") && !forCurrentSpot(data)) {
                // reponse pour un ancien spot (spot change pendant la requete) : on redemande
                registerRefresh();
            } else if (data.hasKey("v")) {
                Application.Storage.setValue("wind", data);
                // heure des dernieres previsions recues (age_h de fetch_error)
                saveState("okAt", Time.now().value());
                Application.Storage.deleteValue("err");
                registerRefresh();
            } else if (data.hasKey("err")) {
                Application.Storage.setValue("err", data["err"]);
                // nouvel essai dans 20 min (le reveil precedent pouvait etre unique)
                Background.registerForTemporalEvent(new Time.Duration(20 * 60));
            }
        }
        WatchUi.requestUpdate();
    }

    // Etat lu par le service : Storage (proprietes ajoutees par une mise a jour parfois absentes)
    // et proprietes (seules lisibles par le service avant Connect IQ 3.2 : fenix 5, vivoactive 3...)
    function saveState(key as String, value) as Void {
        Application.Storage.setValue(key, value);
        try {
            Application.Properties.setValue(key, value);
        } catch (e) {
        }
    }

    function onSettingsChanged() {
        resolveSpot();
        registerRefresh();
        WatchUi.requestUpdate();
    }

    // Prochaine requete calee sur les runs d'AROME HD : quelques minutes apres la mise en ligne
    // attendue du run suivant. Si les donnees sont perimees ou ne partent pas de minuit
    // (ancien format), des requetes repetees toutes les 5 min jusqu'a la prochaine reponse.
    function registerRefresh() {
        var d = Application.Storage.getValue("wind");
        var run = (d instanceof Dictionary) ? d["run"] : null;
        // le service compare ce run aux metadonnees pour eviter un telechargement inutile
        Application.Properties.setValue("runAt", (run instanceof Array) ? run[0] : 0);
        var minutes = refreshMinutes();
        if (needsFetch(run instanceof Array ? staleAfter() : minutes * 60)) {
            // reveil repete toutes les 5 min (immediat si le dernier date de plus de 5 min)
            // jusqu'a la prochaine reponse : un reveil unique restait sans suite si le service
            // n'aboutissait pas sans erreur, et le cadran ne se mettait plus a jour
            Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        } else {
            Background.registerForTemporalEvent(new Time.Duration(nextDelay(run, minutes)));
        }
    }

    function refreshMinutes() {
        var minutes = Application.Properties.getValue("refreshMin");
        if (minutes == null || minutes < 5) {
            minutes = 60;
        }
        return minutes;
    }

    // Delai (s) depuis le dernier reveil jusqu'au prochain : run suivant = debut du dernier run
    // + intervalle + delai de mise en ligne observe + 10 min de marge ; run en retard -> 20 min.
    // La nuit (23 h - 5 h), on saute les runs : le premier du matin suffit.
    // Sans metadonnees : intervalle de secours (reglage, 60 min par defaut).
    function nextDelay(run, minutes) {
        if (!(run instanceof Array)) {
            return minutes * 60;
        }
        var now = Time.now().value();
        var cycle = run[2] + run[1] + 600;
        var next = run[0] + cycle;
        if (next - now < 300) {
            next = now + 1200;
        } else if (next - now > cycle) {
            next = now + run[2];
        }
        while (isNight(next)) {
            next += run[2];
        }
        var last = Background.getLastTemporalEventTime();
        var delay = next - (last != null ? last.value() : now);
        return delay < 300 ? 300 : delay;
    }

    // Nom du modele pour les statistiques (« fr970 »), d'apres le numero de piece Garmin ;
    // lu une seule fois, le service d'arriere-plan envoie le numero de piece si le modele est inconnu
    function resolveModel() {
        var part = System.getDeviceSettings().partNumber;
        var known = Application.Properties.getValue("model");
        if (known != null && !known.equals("") && part.equals(Application.Storage.getValue("modelPart"))) { return; }
        var table = WatchUi.loadResource(Rez.JsonData.Models) as Dictionary;
        var name = table[part];
        Application.Properties.setValue("model", name == null ? part : name);
        Application.Storage.setValue("modelPart", part);
    }

    // Spot effectif : liste « Spot » (telephone) ou menu montre (numero spotId).
    // Recopie dans curName/curLat/curLon, lus par le cadran et le service d'arriere-plan.
    function resolveSpot() {
        var id = Application.Properties.getValue("spotId");
        if (id == null) { id = 0; }
        var seenId = Application.Storage.getValue("seenId");
        var cur = Application.Properties.getValue("curId");
        var newVer = !APP_VERSION.equals(Application.Storage.getValue("nameVer"));
        if (newVer) { Application.Storage.setValue("nameVer", APP_VERSION); }
        if (id == seenId && cur != null && cur >= 0) {
            // nouvelle version : le nom du spot a pu changer dans la liste (1.0.12 : « Ville - Spot »)
            if (newVer && cur > 0) {
                var known = findSpot(cur);
                if (known != null) { Application.Properties.setValue("curName", known[0].toString()); }
            }
            return;
        }
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

    function isNight(t) {
        var h = Gregorian.info(new Time.Moment(t), Time.FORMAT_SHORT).hour;
        return h >= 23 || h < 5;
    }

    function needsFetch(maxAge) {
        var d = Application.Storage.getValue("wind");
        if (!(d instanceof Dictionary) || d["f"] == null || d["t0"] == null) {
            return true;
        }
        if (Time.now().value() - lastContact(d["f"]) > maxAge) {
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
    Application.Storage.deleteValue("chk");
    Application.Storage.deleteValue("err");
    Application.Properties.setValue("runAt", 0);
}

// Dernier contact reussi avec Open-Meteo : donnees recues (f) ou controle « meme run » (chk)
function lastContact(f) {
    var chk = Application.Storage.getValue("chk");
    return (chk != null && chk > f) ? chk : f;
}

// Age (s) au-dela duquel les donnees sont perimees : un run toutes les 3 h le jour,
// rien entre 23 h et 6 h (pause de nuit)
function staleAfter() {
    var h = System.getClockTime().hour;
    return (h >= 23 || h < 7) ? 36000 : 14400;
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
