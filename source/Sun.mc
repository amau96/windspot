import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Lever ou coucher du soleil (secondes epoch) le jour local de « now », au point lat/lon (degres).
// Formules NOAA (equation du temps, declinaison), precision de l'ordre de la minute.
function sunTime(lat as Float, lon as Float, now as Number, rise as Boolean) as Number {
    var tz = System.getClockTime().timeZoneOffset;
    var day = (now + tz) / 86400;              // jour local
    var la = Math.toRadians(lat);
    var info = Gregorian.info(new Time.Moment(now), Time.FORMAT_SHORT);
    var jan1 = Gregorian.moment({ :year => info.year, :month => 1, :day => 1, :hour => 0 });
    var g = 2 * Math.PI / 365.0 * ((now - jan1.value()) / 86400);
    var eqt = 229.18 * (0.000075 + 0.001868 * Math.cos(g) - 0.032077 * Math.sin(g)
        - 0.014615 * Math.cos(2 * g) - 0.040849 * Math.sin(2 * g));
    var dec = 0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g) - 0.006758 * Math.cos(2 * g)
        + 0.000907 * Math.sin(2 * g) - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g);
    var c = Math.cos(Math.toRadians(90.833)) / (Math.cos(la) * Math.cos(dec)) - Math.tan(la) * Math.tan(dec);
    if (c > 1) { c = 1; }       // nuit polaire
    if (c < -1) { c = -1; }     // jour polaire
    var ha = Math.toDegrees(Math.acos(c));
    // minutes UTC depuis minuit UTC du jour local
    var minutes = rise ? 720 - 4 * (lon + ha) - eqt : 720 + 4 * (ha - lon) - eqt;
    return day * 86400 + (minutes * 60).toNumber();
}

// Coordonnees du spot actuel [lat, lon]
function spotCoords() as Array<Float> {
    var lat = Application.Properties.getValue("curLat");
    var lon = Application.Properties.getValue("curLon");
    if (lat == null || lat.toString().equals("")) { lat = Application.Properties.getValue("lat"); }
    if (lon == null || lon.toString().equals("")) { lon = Application.Properties.getValue("lon"); }
    if (lat == null) { lat = "47.46"; }
    if (lon == null) { lon = "-1.46"; }
    return [lat.toString().toFloat(), lon.toString().toFloat()];
}
