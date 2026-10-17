import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Service d'arriere-plan : une requete Open-Meteo (vitesse et direction), fusion des modeles par heure.
// Ordre de priorite : AROME HD, ARPEGE, ICON (premier modele qui a une vitesse ; sa direction avec).
// Avant, lecture des metadonnees d'AROME HD : si aucun nouveau run n'est en ligne, on ne retelecharge pas.
// Une fois par jour (si « Statistiques anonymes » est actif), un evenement Google Analytics :
// identifiant anonyme de l'app sur la montre, modele, version, nom du spot.
(:background)
class WingService extends System.ServiceDelegate {

    // minuit local + 24 h du jour + horizon de la courbe (113 h)
    const MAX_HOURS = 140;

    var lastLat = "";
    var lastLon = "";
    // dernier run AROME en ligne : [debut du run, delai de mise en ligne, intervalle entre runs] (s)
    var runInfo = null;
    // jour local de la statistique envoyee pendant ce reveil (0 : aucune), remonte au cadran
    var pinged = 0;

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() {
        var lat = Application.Properties.getValue("curLat");
        var lon = Application.Properties.getValue("curLon");
        if (lat == null || lat.equals("")) { lat = Application.Properties.getValue("lat"); }
        if (lon == null || lon.equals("")) { lon = Application.Properties.getValue("lon"); }
        if (lat == null) { lat = "47.46"; }
        if (lon == null) { lon = "-1.46"; }
        lastLat = lat.toString();
        lastLon = lon.toString();

        if (!sendDailyStat()) {
            fetchMeta();
        }
    }

    function fetchMeta() as Void {
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest("https://api.open-meteo.com/data/meteofrance_arome_france_hd/static/meta.json", null, options, method(:onMeta));
    }

    // Statistique du jour (Google Analytics, Measurement Protocol) ; la meteo suit dans tous les cas.
    // Renvoie false si rien n'est envoye aujourd'hui (deja fait, desactive ou pas de cle).
    function sendDailyStat() as Boolean {
        var now = Time.now().value();
        var day = (now + System.getClockTime().timeZoneOffset) / 86400;
        var uid = System.getDeviceSettings().uniqueIdentifier;
        if (GA_ID.equals("") || Application.Properties.getValue("stats") == false || uid == null
                || day == Application.Properties.getValue("pingDay")) {
            return false;
        }
        var model = Application.Properties.getValue("model");
        var spot = Application.Properties.getValue("curName");
        var body = {
            "client_id" => uid,
            "events" => [{
                "name" => "daily_active",
                "params" => {
                    "model" => (model == null || model.equals("")) ? System.getDeviceSettings().partNumber : model,
                    "app_version" => APP_VERSION,
                    "spot" => (spot == null) ? "" : spot.toString(),     // nom du spot (« Mazerolles »)
                    "session_id" => day.toString(),
                    "engagement_time_msec" => 1000
                }
            }]
        };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
        };
        pinged = day;
        Communications.makeWebRequest("https://www.google-analytics.com/mp/collect?measurement_id=" + GA_ID
            + "&api_secret=" + GA_SECRET, body, options, method(:onStat));
        return true;
    }

    // Reponse ignoree (une statistique perdue n'est pas grave) ; on enchaine sur la meteo
    function onStat(code as Number, data as Dictionary or String or Null) as Void {
        fetchMeta();
    }

    // Fin du service : le cadran note le jour de la statistique pour ne pas la renvoyer
    function finish(res as Dictionary) as Void {
        if (pinged != 0) { res["ping"] = pinged; }
        Background.exit(res);
    }

    // Metadonnees du modele : meme run que les donnees de la montre -> on s'arrete la ;
    // sinon (ou metadonnees indisponibles) on telecharge les previsions
    function onMeta(code as Number, data as Dictionary or String or Null) as Void {
        if (code == 200 && data instanceof Dictionary) {
            var run = data["last_run_initialisation_time"];
            var avail = data["last_run_availability_time"];
            var iv = data["update_interval_seconds"];
            if (run != null && avail != null && iv != null) {
                runInfo = [run, avail - run, iv];
                var known = Application.Properties.getValue("runAt");
                if (known != null && known == run) {
                    finish({ "same" => runInfo });
                    return;
                }
            }
        }
        fetchForecast();
    }

    // Exactement les heures utiles : depuis minuit (heure locale) jusqu'a MAX_HOURS
    function fetchForecast() as Void {
        var now = Time.now().value();
        var tz = System.getClockTime().timeZoneOffset;
        var midnight = ((now + tz) / 86400) * 86400 - tz;
        var past = (now - midnight) / 3600;
        var params = {
            "latitude" => lastLat,
            "longitude" => lastLon,
            "hourly" => "wind_speed_10m,wind_direction_10m",
            "models" => "meteofrance_arome_france_hd,meteofrance_arpege_europe,icon_seamless",
            "wind_speed_unit" => "kn",
            "past_hours" => past,
            "forecast_hours" => MAX_HOURS - past,
            "timeformat" => "unixtime",
            "timezone" => "GMT"
        };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest("https://api.open-meteo.com/v1/forecast", params, options, method(:onReceive));
    }

    // Erreurs : code Garmin/HTTP de la requete, ou 1001-1004 si la reponse est inexploitable
    function onReceive(code as Number, data as Dictionary or String or Null) as Void {
        if (code != 200 || !(data instanceof Dictionary)) {
            finish({ "err" => code });
            return;
        }
        var hourly = data["hourly"];
        if (!(hourly instanceof Dictionary)) {
            finish({ "err" => 1001 });
            return;
        }
        var times = hourly["time"];
        if (times == null || times.size() == 0) {
            finish({ "err" => 1002 });
            return;
        }

        var models = ["meteofrance_arome_france_hd", "meteofrance_arpege_europe", "icon_seamless"];
        var speeds = [];
        var dirs = [];
        for (var k = 0; k < models.size(); k++) {
            var s = hourly["wind_speed_10m_" + models[k]];
            if (s != null) {
                speeds.add(s);
                dirs.add(hourly["wind_direction_10m_" + models[k]]);
            }
        }
        if (speeds.size() == 0) {
            finish({ "err" => 1003 });
            return;
        }

        // on garde les donnees depuis minuit (heure locale) pour le pic de la journee
        var now = Time.now().value();
        var tz = System.getClockTime().timeZoneOffset;
        var midnight = ((now + tz) / 86400) * 86400 - tz;
        var start = times[0];
        var off = (midnight - start) / 3600;
        if (off < 0) { off = 0; }

        var outV = [];
        var outD = [];
        var total = times.size() - off;
        if (total > MAX_HOURS) { total = MAX_HOURS; }
        for (var i = 0; i < total; i++) {
            var j = off + i;
            var v = null;
            var dir = null;
            for (var k = 0; k < speeds.size(); k++) {
                var s = speeds[k];
                if (j < s.size() && s[j] != null) {
                    v = s[j];
                    var ds = dirs[k];
                    if (ds != null && j < ds.size()) { dir = ds[j]; }
                    break;
                }
            }
            if (v == null) {
                break;
            }
            // dixiemes de noeud, entier ; direction en degres (d'ou vient le vent), -1 si absente
            outV.add((v.toFloat() * 10 + 0.5).toNumber());
            outD.add(dir == null ? -1 : dir.toNumber());
        }

        if (outV.size() == 0) {
            finish({ "err" => 1004 });
            return;
        }
        // coordonnees demandees : le cadran ignore la reponse si le spot a change entre-temps
        var res = { "t0" => start + off * 3600, "v" => outV, "d" => outD, "f" => now, "lat" => lastLat, "lon" => lastLon };
        if (runInfo != null) { res["run"] = runInfo; }
        finish(res);
    }
}
