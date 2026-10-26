import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Service d'arriere-plan : requete Open-Meteo (vitesse et direction), fusion des modeles par heure.
// Ordre de priorite : AROME HD, ARPEGE, ICON (premier modele qui a une vitesse ; sa direction avec).
// Avant, lecture des metadonnees d'AROME HD : si aucun nouveau run n'est en ligne, on ne retelecharge pas.
// Statistiques Google Analytics (si « Statistiques anonymes » est actif) : une fois par jour, et a
// l'installation, a la mise a jour, au changement de spot ; identifiant anonyme de l'app sur la
// montre, modele, version, nom du spot.
(:background)
class WingService extends System.ServiceDelegate {

    // minuit local + 24 h du jour + horizon de la courbe (113 h)
    const MAX_HOURS = 140;

    var lastLat = "";
    var lastLon = "";
    // dernier run AROME en ligne : [debut du run, delai de mise en ligne, intervalle entre runs] (s)
    var runInfo = null;
    // statistiques envoyees pendant ce reveil : [jour, version, spot] (null : aucune), remonte au cadran
    var pinged = null;
    // resultat meteo, rendu au cadran une fois les statistiques envoyees
    var result = {};
    // code de la requete des metadonnees (envoye avec fetch_error)
    var metaCode = 0;
    // derniere erreur de requete meteo, pour l'evenement fetch_error : parametres GA
    var errInfo = null;
    // fetch_error envoye pendant ce reveil : [jour, code], remonte au cadran
    var errPinged = null;
    // erreur gardee par le cadran faute de connexion (errPend), envoyee pendant ce reveil
    var pendSent = false;
    // parametres d'une erreur gardee, dans l'ordre (texte separe par « | », heure de l'erreur en tete)
    const ERR_KEYS = ["code", "step", "models", "hours", "mem_free", "mem_total", "phone", "meta", "age_h"];

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() {
        var lat = bgProp("curLat", "");
        var lon = bgProp("curLon", "");
        if (lat.equals("")) { lat = bgProp("lat", "47.46"); }
        if (lon.equals("")) { lon = bgProp("lon", "-1.46"); }
        lastLat = lat.toString();
        lastLon = lon.toString();

        // la meteo d'abord : les statistiques partent apres, quand le resultat est pret
        fetchMeta();
    }

    function fetchMeta() as Void {
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest("https://api.open-meteo.com/data/meteofrance_arome_france_hd/static/meta.json", null, options, method(:onMeta));
    }

    // Statistiques (Google Analytics, Measurement Protocol), en une seule requete, apres la meteo.
    //  - install        : premier envoi depuis cette montre (installation, ou premiere version avec statistiques)
    //  - version_update : version differente de celle du dernier envoi (previous_version)
    //  - spot_change    : spot different de celui du dernier envoi
    //  - daily_active   : une fois par jour
    //  - fetch_error    : requete meteo en echec (une fois par jour et par code), avec de quoi chercher
    //                     la cause : etape, modeles, heures deja recues, memoire, telephone connecte
    //                     ; sans connexion, gardee par le cadran et envoyee au retour (delay_h)
    // Renvoie false si rien n'est a envoyer (deja fait, desactive ou pas de cle).
    // Etat des envois dans Storage et dans les proprietes (pingDay, pingVer, pingSpot), voir pingValue.
    function sendStats() as Boolean {
        var uid = System.getDeviceSettings().uniqueIdentifier;
        if (GA_ID.equals("") || bgProp("stats", true) == false || uid == null) {
            return false;
        }
        var day = (Time.now().value() + System.getClockTime().timeZoneOffset) / 86400;
        var lastDay = pingValue("pingDay", 0);
        var lastVer = pingValue("pingVer", "");
        var lastSpot = pingValue("pingSpot", "");
        var model = bgProp("model", "");
        if (model.equals("")) { model = System.getDeviceSettings().partNumber; }
        var spot = bgProp("curName", "").toString();     // nom du spot (« Mazerolles »)

        var events = [];
        if (lastVer.equals("")) {
            events.add(statEvent("install", model, spot, day, null));
        } else if (!lastVer.equals(APP_VERSION)) {
            events.add(statEvent("version_update", model, spot, day, lastVer));
        }
        if (!lastSpot.equals("") && !spot.equals("") && !lastSpot.equals(spot)) {
            events.add(statEvent("spot_change", model, spot, day, null));
        }
        if (day != lastDay) {
            events.add(statEvent("daily_active", model, spot, day, null));
        }
        if (errInfo != null && !(pingValue("errDay", 0) == day && pingValue("errCode", 0) == errInfo["code"])) {
            var ev = statEvent("fetch_error", model, spot, day, null);
            var params = ev["params"] as Dictionary;
            var keys = errInfo.keys();
            for (var i = 0; i < keys.size(); i++) { params[keys[i]] = errInfo[keys[i]]; }
            events.add(ev);
            errPinged = [day, errInfo["code"]];
        }
        // erreur d'un reveil precedent qui n'a pas pu partir (pas de connexion) : delay_h = heures
        // entre l'erreur et cet envoi, soit la duree de la coupure vue par la montre
        var pend = pingValue("errPend", "").toString();
        if (!pend.equals("")) {
            var f = splitPend(pend);
            if (f.size() == ERR_KEYS.size() + 1) {
                var pev = statEvent("fetch_error", model, spot, day, null);
                var pp = pev["params"] as Dictionary;
                for (var j = 0; j < ERR_KEYS.size(); j++) { pp[ERR_KEYS[j]] = f[j + 1]; }
                var at = f[0].toNumber();
                pp["delay_h"] = (at != null) ? (Time.now().value() - at) / 3600 : -1;
                events.add(pev);
            }
            pendSent = true;
        }
        if (events.size() == 0) {
            return false;
        }
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
        };
        // remonte au cadran ce qui a ete envoye (jour, version, spot) pour ne pas le renvoyer
        pinged = [(day != lastDay) ? day : lastDay, APP_VERSION, spot.equals("") ? lastSpot : spot];
        Communications.makeWebRequest("https://www.google-analytics.com/mp/collect?measurement_id=" + GA_ID
            + "&api_secret=" + GA_SECRET, { "client_id" => uid, "events" => events }, options, method(:onStat));
        return true;
    }

    function statEvent(name as String, model, spot as String, day as Number, previous) as Dictionary {
        var params = {
            "model" => model,
            "app_version" => APP_VERSION,
            "spot" => spot,
            "session_id" => day.toString(),
            "engagement_time_msec" => 1000
        };
        if (previous != null) { params["previous_version"] = previous; }
        return { "name" => name, "params" => params };
    }

    // Envoi reussi : le cadran note ce qui est parti. Echec (pas de connexion) : rien n'est note,
    // tout repart au reveil suivant, et une erreur meteo est gardee par le cadran (errPend) pour
    // ne pas la perdre ; on garde la premiere, debut de la coupure. Puis on rend le resultat meteo.
    function onStat(code as Number, data as Dictionary or String or Null) as Void {
        if (code >= 200 && code < 300) {
            if (pinged != null) { result["ping"] = pinged; }
            if (errPinged != null) { result["errPing"] = errPinged; }
            if (pendSent) { result["errPend"] = ""; }
        } else if (errPinged != null && !pendSent) {
            var s = Time.now().value().toString();
            for (var i = 0; i < ERR_KEYS.size(); i++) { s += "|" + errInfo[ERR_KEYS[i]]; }
            result["errPend"] = s;
        }
        Background.exit(result);
    }

    // « a|b|c » -> ["a", "b", "c"]
    function splitPend(s as String) as Array {
        var out = [];
        var i = s.find("|");
        while (i != null) {
            out.add(s.substring(0, i));
            s = s.substring(i + 1, s.length());
            i = s.find("|");
        }
        out.add(s);
        return out;
    }

    // Fin de la meteo : statistiques s'il y en a a envoyer, puis fin du service. Une erreur dans
    // les statistiques ne doit jamais bloquer la meteo (1.0.10 : propriete absente apres une mise
    // a jour depuis la 1.0.8, le service plantait avant la requete et le cadran restait sans donnees).
    function finish(res as Dictionary) as Void {
        result = res;
        var sent = false;
        try {
            sent = sendStats();
        } catch (e) {
            pinged = null;
            errPinged = null;
            pendSent = false;
        }
        if (!sent) {
            Background.exit(res);
        }
    }

    // Metadonnees du modele : meme run que les donnees de la montre -> on s'arrete la ;
    // sinon (ou metadonnees indisponibles) on telecharge les previsions
    function onMeta(code as Number, data as Dictionary or String or Null) as Void {
        metaCode = code;
        if (code == 200 && data instanceof Dictionary) {
            var run = data["last_run_initialisation_time"];
            var avail = data["last_run_availability_time"];
            var iv = data["update_interval_seconds"];
            if (run != null && avail != null && iv != null) {
                runInfo = [run, avail - run, iv];
                var known = bgProp("runAt", 0);
                if (known == run) {
                    finish({ "same" => runInfo });
                    return;
                }
            }
        }
        fetchForecast();
    }

    // Une requete pour les trois modeles ; sur les montres ou le service n'a que 32 Ko (fenix 6,
    // vivoactive 3...), la reponse ne tient pas en memoire (-403) : une requete par modele,
    // enchainees dans le meme reveil, chacune ne remplissant que les heures encore vides.
    const MODELS = ["meteofrance_arome_france_hd", "meteofrance_arpege_europe", "icon_seamless"];
    const SHORT = ["arome", "arpege", "icon"];
    var groups = null;  // modeles de chaque requete
    var step = 0;       // requete en cours
    var t0 = 0;         // debut des donnees (minuit local, s)
    var outV = null;    // vitesses fusionnees (dixiemes de noeud), null : heure encore vide
    var outD = null;    // directions (degres, -1 si absente)

    // Exactement les heures utiles : depuis minuit (heure locale) jusqu'a MAX_HOURS
    function fetchForecast() as Void {
        if (groups == null) {
            groups = (System.getSystemStats().totalMemory < 48 * 1024) ? [[MODELS[0]], [MODELS[1]], [MODELS[2]]] : [MODELS];
        }
        var models = groups[step] as Array;
        var list = "";
        for (var k = 0; k < models.size(); k++) {
            list += (k > 0 ? "," : "") + models[k];
        }
        var now = Time.now().value();
        var tz = System.getClockTime().timeZoneOffset;
        var midnight = ((now + tz) / 86400) * 86400 - tz;
        var past = (now - midnight) / 3600;
        var params = {
            "latitude" => lastLat,
            "longitude" => lastLon,
            "hourly" => "wind_speed_10m,wind_direction_10m",
            "models" => list,
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

    // Erreurs : code Garmin/HTTP de la requete, ou 1001-1004 si la reponse est inexploitable.
    // Erreur sur une requete suivante : on garde les heures deja remplies.
    function onReceive(code as Number, data as Dictionary or String or Null) as Void {
        var err = 0;
        if (code != 200 || !(data instanceof Dictionary)) {
            err = code;
        } else {
            err = merge(data);
        }
        data = null;
        if (err != 0) { noteError(err); }
        if (err != 0 && step == 0) {
            finish({ "err" => err });
            return;
        }
        step++;
        if (err == 0 && step < groups.size() && outV.indexOf(null) >= 0) {
            fetchForecast();
            return;
        }
        done();
    }

    // Erreur de requete : etat au moment de l'echec, pour fetch_error (memoire mesuree ici :
    // -403 = reponse trop grosse pour la memoire du service)
    function noteError(code as Number) as Void {
        var st = System.getSystemStats();
        var i = (step < groups.size()) ? step : groups.size() - 1;
        var models = groups[i] as Array;
        var names = "";
        for (var k = 0; k < models.size(); k++) {
            names += (k > 0 ? "," : "") + SHORT[MODELS.indexOf(models[k])];
        }
        var okAt = pingValue("okAt", 0);
        errInfo = {
            "code" => code,
            "step" => (i + 1).toString() + "/" + groups.size(),
            "models" => names,
            "hours" => (outV == null) ? 0 : (outV.indexOf(null) < 0 ? outV.size() : outV.indexOf(null)),
            "mem_free" => st.freeMemory,
            "mem_total" => st.totalMemory,
            "phone" => System.getDeviceSettings().phoneConnected ? 1 : 0,
            "meta" => metaCode,
            "age_h" => (okAt > 0) ? (Time.now().value() - okAt) / 3600 : -1
        };
    }

    // Remplit les heures encore vides avec les modeles de la reponse, dans l'ordre de priorite
    // (premier modele qui a une vitesse ; sa direction avec). Renvoie 0, ou 1001-1003.
    function merge(data as Dictionary) as Number {
        var hourly = data["hourly"];
        if (!(hourly instanceof Dictionary)) {
            return 1001;
        }
        var times = hourly["time"];
        if (times == null || times.size() == 0) {
            return 1002;
        }
        var start = times[0];
        if (outV == null) {
            // on garde les donnees depuis minuit (heure locale) pour le pic de la journee
            var now = Time.now().value();
            var tz = System.getClockTime().timeZoneOffset;
            var midnight = ((now + tz) / 86400) * 86400 - tz;
            var off = (midnight - start) / 3600;
            if (off < 0) { off = 0; }
            t0 = start + off * 3600;
            var total = times.size() - off;
            if (total > MAX_HOURS) { total = MAX_HOURS; }
            if (total < 0) { total = 0; }
            outV = new [total];
            outD = new [total];
        }
        var models = groups[step] as Array;
        var found = false;
        for (var k = 0; k < models.size(); k++) {
            // un seul modele demande : cles sans suffixe (« wind_speed_10m »)
            var suffix = (models.size() == 1) ? "" : "_" + models[k];
            var s = hourly["wind_speed_10m" + suffix];
            if (s == null) { continue; }
            found = true;
            var ds = hourly["wind_direction_10m" + suffix];
            for (var i = 0; i < outV.size(); i++) {
                var j = (t0 - start) / 3600 + i;
                if (outV[i] != null || j < 0 || j >= s.size() || s[j] == null) { continue; }
                // dixiemes de noeud, entier ; direction en degres (d'ou vient le vent), -1 si absente
                outV[i] = (s[j].toFloat() * 10 + 0.5).toNumber();
                outD[i] = (ds != null && j < ds.size() && ds[j] != null) ? ds[j].toNumber() : -1;
            }
        }
        return found ? 0 : 1003;
    }

    // Resultat : heures remplies sans trou depuis minuit
    function done() as Void {
        var n = (outV == null) ? -1 : outV.indexOf(null);
        if (n < 0) { n = (outV == null) ? 0 : outV.size(); }
        if (n == 0) {
            noteError(1004);
            finish({ "err" => 1004 });
            return;
        }
        // coordonnees demandees : le cadran ignore la reponse si le spot a change entre-temps
        var res = { "t0" => t0, "v" => outV.slice(0, n), "d" => outD.slice(0, n), "f" => Time.now().value(), "lat" => lastLat, "lon" => lastLon };
        if (runInfo != null) { res["run"] = runInfo; }
        outV = null;
        outD = null;
        finish(res);
    }
}

// Propriete lue depuis le service : une propriete ajoutee par une mise a jour peut manquer
// (exception a la lecture) ; valeur par defaut si absente, nulle ou d'un autre type
(:background)
function bgProp(key as String, def) {
    var v = def;
    try {
        var p = Application.Properties.getValue(key);
        if (p != null) { v = p; }
    } catch (e) {
        return def;
    }
    if (def instanceof Lang.String) { return v.toString(); }
    if ((def instanceof Lang.Number) && !(v instanceof Lang.Number)) { return def; }
    if ((def instanceof Lang.Boolean) && !(v instanceof Lang.Boolean)) { return def; }
    return v;
}

// Etat des statistiques : Storage (ecrit par le cadran), sinon proprietes (copie ecrite par le
// cadran ; Storage illisible ici avant Connect IQ 3.2)
(:background)
function pingValue(key as String, def) {
    var v = null;
    try {
        v = Application.Storage.getValue(key);
    } catch (e) {
        v = null;
    }
    return (v != null) ? v : bgProp(key, def);
}
