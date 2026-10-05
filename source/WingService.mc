import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Service d'arriere-plan : une requete Open-Meteo, fusion des modeles par heure.
// Ordre de priorite : AROME HD, ARPEGE, ICON, GFS (premiere valeur non nulle).
(:background)
class WingService extends System.ServiceDelegate {

    // minuit local + 24 h du jour + horizon de la courbe (113 h)
    const MAX_HOURS = 140;

    // resultat de la 1re requete (vitesse), complete par la 2e (direction)
    var result = null;
    var lastLat = "";
    var lastLon = "";
    var dirOff = 0;

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

        var params = {
            "latitude" => lastLat,
            "longitude" => lastLon,
            "hourly" => "wind_speed_10m",
            "models" => "meteofrance_arome_france_hd,meteofrance_arpege_europe,icon_seamless,gfs_seamless",
            "wind_speed_unit" => "kn",
            "forecast_days" => 6,
            "past_days" => 1,
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

    function onReceive(code as Number, data as Dictionary or String or Null) as Void {
        if (code != 200 || !(data instanceof Dictionary)) {
            Background.exit({ "err" => code });
            return;
        }
        var hourly = data["hourly"];
        if (!(hourly instanceof Dictionary)) {
            Background.exit({ "err" => -1 });
            return;
        }
        var times = hourly["time"];
        if (times == null || times.size() == 0) {
            Background.exit({ "err" => -2 });
            return;
        }

        var keys = [
            "wind_speed_10m_meteofrance_arome_france_hd",
            "wind_speed_10m_meteofrance_arpege_europe",
            "wind_speed_10m_icon_seamless",
            "wind_speed_10m_gfs_seamless"
        ];
        var series = [];
        for (var k = 0; k < keys.size(); k++) {
            var s = hourly[keys[k]];
            if (s != null) {
                series.add(s);
            }
        }
        if (series.size() == 0) {
            Background.exit({ "err" => -3 });
            return;
        }

        // on garde les donnees depuis minuit (heure locale) pour le pic de la journee
        var now = Time.now().value();
        var tz = System.getClockTime().timeZoneOffset;
        var midnight = ((now + tz) / 86400) * 86400 - tz;
        var start = times[0];
        var off = (midnight - start) / 3600;
        if (off < 0) { off = 0; }

        var out = [];
        var total = times.size() - off;
        if (total > MAX_HOURS) { total = MAX_HOURS; }
        for (var i = 0; i < total; i++) {
            var v = null;
            for (var k = 0; k < series.size(); k++) {
                var s = series[k];
                if (off + i < s.size()) {
                    var x = s[off + i];
                    if (x != null) {
                        v = x;
                        break;
                    }
                }
            }
            if (v == null) {
                break;
            }
            // dixiemes de noeud, entier
            out.add((v.toFloat() * 10 + 0.5).toNumber());
        }

        if (out.size() == 0) {
            Background.exit({ "err" => -4 });
            return;
        }
        // 2e requete, petite : direction du vent (modele « meilleur choix » d'Open-Meteo), memes heures
        // coordonnees demandees : le cadran ignore la reponse si le spot a change entre-temps
        result = { "t0" => start + off * 3600, "v" => out, "f" => now, "lat" => lastLat, "lon" => lastLon };
        dirOff = off;
        series = null;
        hourly = null;
        data = null;
        var params = {
            "latitude" => lastLat,
            "longitude" => lastLon,
            "hourly" => "wind_direction_10m",
            "forecast_days" => 6,
            "past_days" => 1,
            "timeformat" => "unixtime",
            "timezone" => "GMT"
        };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest("https://api.open-meteo.com/v1/forecast", params, options, method(:onReceiveDir));
    }

    // Directions (degres, d'ou vient le vent) alignees sur les vitesses ; si echec, on garde les vitesses seules
    function onReceiveDir(code as Number, data as Dictionary or String or Null) as Void {
        var res = result;
        if (code == 200 && data instanceof Dictionary) {
            var hourly = data["hourly"];
            if (hourly instanceof Dictionary && hourly["wind_direction_10m"] != null) {
                var src = hourly["wind_direction_10m"];
                var n = (res["v"] as Array).size();
                var dirs = [];
                for (var i = 0; i < n; i++) {
                    var x = (dirOff + i < src.size()) ? src[dirOff + i] : null;
                    dirs.add(x == null ? -1 : x.toNumber());
                }
                res["d"] = dirs;
            }
        }
        Background.exit(res);
    }
}
