import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Cadran vent pour la wing : anneau 24 h sur la lunette, courbe 5 jours en bas.
// Toutes les valeurs de vent sont en dixiemes de noeud (entiers).
class WingFaceView extends WatchUi.WatchFace {

    // Seuils (dixiemes de noeud) : <8 bleu, 8-12 bleu ciel, 12-16 vert, 16-20 jaune, 20-25 orange, >25 rouge
    const COLORS = [0x3A78D0, 0x4FB8F0, 0x7BDB4A, 0xF2C037, 0xF08A24, 0xE24B4A];
    const DIM_COLORS = [0x1A3766, 0x235A78, 0x3D6D25, 0x7A601C, 0x78450F, 0x712524];
    // Ecrans MIP 64 couleurs (fenix 6) : teintes exactes de la palette, sinon le jaune vire a l'orange
    const MIP_COLORS = [0x5555FF, 0x00AAFF, 0x55FF55, 0xFFFF55, 0xFFAA00, 0xFF5555];
    var colors = COLORS;
    var dimColors = DIM_COLORS;
    var calmText = 0x8A9BB8;
    const PAST_COLOR = 0x1C1C1C;
    const LOST_AFTER = 43200;      // 12 h sans prevision : la courbe laisse place a un message
    const STALE_COLOR = 0x8A8880;  // vent affiche en gris quand les donnees sont trop anciennes
    // Couleurs des textes (AMOLED) ; ecrans MIP : couleurs exactes de la palette 64 couleurs, plus
    // contrastees (blanc / gris clair), les teintes intermediaires y etant approchees et ternes
    var cDate = 0xE6E4DC;    // date
    var cInfo = 0xC8C6BE;    // ligne du haut, titre de chargement
    var cDays = 0xD0CEC6;    // jours sous la courbe
    var cSoft = 0x9A9890;    // pic du jour, nom du spot
    var cSoft2 = 0x8F8D86;   // lignes d'aide du chargement
    var cLine = 0x999999;    // ligne pointillee des 12 nd
    var cSep = 0x777777;     // separations des jours
    var cStale = STALE_COLOR;
    var cHour = 0xDCDAF2;    // heures
    const RING_LEVEL = 0.55; // luminosite des couleurs de l'anneau sur AMOLED (1 = couleurs pleines)
    var ringLevel = RING_LEVEL;
    const PAST_STYLE = 3;    // heures passees : 1 = vent passe tres sombre, 2 = trait fin gris, 3 = trait fin couleur sombre
    const PAST_LEVEL = 0.2;
    const CAP = 280;
    const HORIZON = 113;
    const DAYS = ["dim", "lun", "mar", "mer", "jeu", "ven", "sam"];
    const DAYS2 = ["di", "lu", "ma", "me", "je", "ve", "sa"];
    const DAYS1 = ["D", "L", "M", "M", "J", "V", "S"];
    const MONTHS = ["janv.", "fevr.", "mars", "avr.", "mai", "juin", "juil.", "aout", "sept.", "oct.", "nov.", "dec."];

    var inSleep = false;
    var vals = null;
    var t0 = 0;
    var fetchedAt = 0;
    var testMode = false;
    var dirs = null;     // direction du vent par heure (degres, d'ou il vient), -1 si inconnue
    var curVal = 0;      // vent actuel, interpole entre l'heure en cours et la suivante (dixiemes de noeud)
    var curDir = -1;     // direction actuelle, interpolee de meme (-1 si inconnue)
    var stale = false;   // donnees trop anciennes (pas de contact avec Open-Meteo)
    var lost = false;    // plus rien depuis LOST_AFTER : message a la place de la courbe
    var fontMid = null;
    var fontLabel = Graphics.FONT_XTINY;
    var fontLoad = Graphics.FONT_XTINY;
    var small = false;
    var tiny = false;    // tres petit ecran (218 px) sans police vectorielle : courbe plus etroite, heure plus haute
    var amoled = false;  // ecran AMOLED : veille allegee (limite de pixels allumes, marquage)   // petit ecran (<= 240 px) sans police vectorielle : affichage allege

    function initialize() {
        WatchFace.initialize();
    }

    // Police des cadrans Garmin (Roboto Condensed Bold), sinon police numerique standard
    function timeFont(px, fallback) {
        if (Graphics has :getVectorFont) {
            var f = Graphics.getVectorFont({ :face => ["RobotoCondensedBold", "RobotoRegular"], :size => px });
            if (f != null) { return f; }
        }
        return fallback;
    }

    function onLayout(dc) {
        var u = dc.getWidth() / 340.0;
        // sans police vectorielle (fenix 6) : la plus grande police de chiffres (57 px sur 260)
        fontMid = timeFont((104 * u).toNumber(), Graphics.FONT_NUMBER_THAI_HOT);
        fontLabel = timeFont((15 * u).toNumber(), Graphics.FONT_XTINY);
        fontLoad = timeFont((19 * u).toNumber(), Graphics.FONT_XTINY);
        small = dc.getWidth() <= 240 && !(Graphics has :getVectorFont);
        subscribeInfos();
        tiny = small && dc.getWidth() <= 218;
        // ecran MIP (64 couleurs, pas de marquage) : couleurs pleines, l'attenuation fausse les teintes
        var ds = System.getDeviceSettings();
        amoled = (ds has :requiresBurnInProtection) && ds.requiresBurnInProtection;
        ringLevel = amoled ? RING_LEVEL : 1.0;
        if (!amoled) {
            colors = MIP_COLORS;
            dimColors = MIP_COLORS;
            calmText = 0xAAAAAA;
            cDate = 0xFFFFFF;
            cInfo = 0xFFFFFF;
            cDays = 0xFFFFFF;
            cSoft = 0xAAAAAA;
            cSoft2 = 0xAAAAAA;
            cLine = 0xAAAAAA;
            cSep = 0xAAAAAA;
            cStale = 0xAAAAAA;
            cHour = 0xFFFFFF;
        }
    }

    function onEnterSleep() {
        inSleep = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() {
        inSleep = false;
        WatchUi.requestUpdate();
    }

    function prop(id, def) {
        var v = Application.Properties.getValue(id);
        return (v == null) ? def : v;
    }

    // ---------- donnees ----------

    function loadData() {
        testMode = (prop("testMode", false) == true);
        if (testMode) {
            buildTest();
            return;
        }
        var d = Application.Storage.getValue("wind");
        if (d instanceof Dictionary) {
            vals = d["v"];
            dirs = d.hasKey("d") ? d["d"] : null;
            t0 = d["t0"];
            fetchedAt = lastContact(d["f"]);
        } else {
            vals = null;
        }
    }

    // Mode test : heure figee a 10 h 23, donnees depuis minuit.
    // Aujourd'hui : calme le matin, 15 nd vers 13 h, pic 18 nd vers 15 h, retombe le soir.
    // Jours suivants : pics de 24, 10, 15, 27 et 12 nd vers 14 h.
    const TEST_TODAY = [4, 4, 3, 3, 3, 4, 5, 6, 7, 8, 9, 11, 13, 15, 17, 18, 18, 16, 14, 12, 10, 8, 6, 5];
    const TEST_PEAKS = [24, 10, 15, 27, 12];
    var testNow = 0;

    function buildTest() {
        t0 = Time.today().value();
        testNow = t0 + 10 * 3600 + 23 * 60;
        fetchedAt = testNow;
        var arr = [];
        for (var h = 0; h < 24; h++) {
            arr.add(TEST_TODAY[h] * 10);
        }
        for (var d = 0; d < TEST_PEAKS.size(); d++) {
            for (var h = 0; h < 24; h++) {
                var s = 0.25;
                if (h > 8 && h < 20) {
                    s = 0.25 + 0.75 * Math.sin(Math.PI * (h - 8) / 12.0);
                }
                var v = TEST_PEAKS[d] * s + 1.0 * Math.sin(h * 1.7);
                if (v < 2.0) { v = 2.0; }
                arr.add((v * 10).toNumber());
            }
        }
        vals = arr;
        var d = [];
        for (var i = 0; i < arr.size(); i++) {
            d.add((250 + 40 * Math.sin(i / 7.0)).toNumber() % 360);
        }
        dirs = d;
    }

    function nowSec() {
        return testMode ? testNow : Time.now().value();
    }

    function clockNow() {
        return testMode ? new TestClock(10, 23) : System.getClockTime();
    }

    // Tranche de couleur d'apres le vent arrondi au noeud, comme le chiffre affiche
    // (15,6 nd s'affiche « 16 nd » : il doit etre jaune, pas vert)
    function band(t) {
        var k = (t + 5) / 10;
        if (k < 8) { return 0; }
        if (k < 12) { return 1; }
        if (k < 16) { return 2; }
        if (k < 20) { return 3; }
        if (k < 25) { return 4; }
        return 5;
    }

    function windColor(t) {
        if (band(t) == 0) { return calmText; }
        return colors[band(t)];
    }

    function knots(t) {
        return ((t + 5) / 10).toString() + " nd";
    }

    // ---------- affichage ----------

    function onUpdate(dc) {
        var w = dc.getWidth();
        var cx = w / 2;
        var cy = dc.getHeight() / 2;
        var u = w / 340.0;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        loadData();

        var clock = clockNow();
        var now = nowSec();
        var off = 0;
        var n = 0;
        if (vals != null) {
            off = (now - t0) / 3600;
            if (off < 0) { off = 0; }
            n = vals.size() - off;
            if (n > HORIZON) { n = HORIZON; }
            if (n < 1) { n = 0; }
        }

        if (n > 0) {
            interpolateNow(off, clock.min);
        }
        stale = (vals != null && !testMode && (now - fetchedAt) > staleAfter());
        lost = stale && (now - fetchedAt) > LOST_AFTER;

        // veille allegee seulement sur AMOLED ; un ecran MIP (toujours allume) garde l'ecran complet
        if (inSleep && amoled) {
            drawSleep(dc, cx, cy, u, clock, off, n);
        } else if (n == 0) {
            drawLoadingScreen(dc, cx, cy, u, clock);
        } else {
            drawMain(dc, cx, cy, u, clock, off, n);
        }
    }

    // Vent « maintenant » : prevision de l'heure en cours et de la suivante, ponderees par les minutes
    // (la prevision est horaire ; sans ca, la valeur saute d'un coup a chaque heure pile)
    function interpolateNow(off, min) {
        var f = min / 60.0;
        var v0 = vals[off];
        var hasNext = off + 1 < vals.size();
        curVal = hasNext ? (v0 + (vals[off + 1] - v0) * f + 0.5).toNumber() : v0;
        curDir = (dirs != null && off < dirs.size()) ? dirs[off] : -1;
        if (curDir >= 0 && hasNext && off + 1 < dirs.size() && dirs[off + 1] >= 0) {
            // par le plus court chemin (350 -> 10 passe par 0, pas par 180)
            var diff = ((dirs[off + 1] - curDir + 540) % 360) - 180;
            curDir = ((curDir + diff * f + 360).toNumber()) % 360;
        }
    }

    function lerpColor(a, b, t) {
        var r = ((a >> 16) & 0xFF) + ((((b >> 16) & 0xFF) - ((a >> 16) & 0xFF)) * t).toNumber();
        var g = ((a >> 8) & 0xFF) + ((((b >> 8) & 0xFF) - ((a >> 8) & 0xFF)) * t).toNumber();
        var bl = (a & 0xFF) + (((b & 0xFF) - (a & 0xFF)) * t).toNumber();
        return (r << 16) | (g << 8) | bl;
    }

    // Degrade des minutes facon cadran Garmin : vert -> cyan -> bleu
    const GRAD = [0x35E07A, 0x1FC9D6, 0x2F7FF0];

    // MIP : trois couleurs exactes de la palette (vert, cyan, bleu) en paliers, sans teintes intermediaires
    const GRAD_MIP = [0x55FF55, 0x00FFFF, 0x00AAFF];

    function gradColor(t) {
        if (!amoled) { return GRAD_MIP[t < 0.34 ? 0 : (t < 0.67 ? 1 : 2)]; }
        if (t < 0.5) { return lerpColor(GRAD[0], GRAD[1], t * 2); }
        return lerpColor(GRAD[1], GRAD[2], (t - 0.5) * 2);
    }

    // Texte en degrade horizontal, dessine par bandes verticales (clip), aligne a gauche sur x
    function drawGradientText(dc, x, y, font, txt) {
        var w = dc.getTextWidthInPixels(txt, font);
        var h = dc.getHeight();
        var step = 3;
        for (var xx = x; xx < x + w; xx += step) {
            dc.setClip(xx, 0, step, h);
            dc.setColor(gradColor((xx - x).toFloat() / w), Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, font, txt, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        dc.clearClip();
    }

    function hourString(clock) {
        var h = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            h = h % 12;
            if (h == 0) { h = 12; }
        }
        return h.format("%02d");
    }

    // Heure sur une ligne : heures pales, minutes en degrade
    function drawTimeLine(dc, cx, y, font, clock) {
        var hs = hourString(clock) + ":";
        var ms = clock.min.format("%02d");
        var wh = dc.getTextWidthInPixels(hs, font);
        var x = cx - (wh + dc.getTextWidthInPixels(ms, font)) / 2;
        dc.setColor(cHour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, hs, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        drawGradientText(dc, x + wh, y, font, ms);
    }

    function timeString(clock) {
        var h = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            h = h % 12;
            if (h == 0) { h = 12; }
        }
        return (System.getDeviceSettings().is24Hour ? h.format("%02d") : h.toString()) + ":" + clock.min.format("%02d");
    }

    // Ligne de date : emplacement 3 de l'editeur natif s'il est choisi, sinon notre date
    function topDateText() {
        var t = dateSlotText();
        return (t != null && !t.equals("")) ? t : dateString();
    }

    function dateString() {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return DAYS[info.day_of_week - 1] + ". " + info.day.toString() + " " + MONTHS[info.month - 1];
    }

    // Ligne du haut : donnees choisies, puis « MAJ 5h » si les donnees vent sont anciennes.
    // Si le tout ne tient pas dans le cercle a cette hauteur, on retire les dernieres donnees
    // (l'indicateur MAJ reste).
    function drawTopLine(dc, cx, y, now) {
        var infos = infoTexts();
        var tail = "";
        if (stale && !lost) {
            // age des donnees, par ex. « MAJ 5h » (le vent est aussi affiche en gris)
            tail = "MAJ " + ((now - fetchedAt) / 3600).toString() + "h";
        } else if (testMode) {
            tail = "TEST";
        }
        var u = dc.getWidth() / 340.0;
        var dy = (y - dc.getHeight() / 2).abs();
        var rIn = 156 * u;
        var room = (dy < rIn) ? (2 * Math.sqrt(rIn * rIn - dy * dy)).toNumber() : 0;
        var n = infos.size();
        var txt = "";
        while (true) {
            txt = "";
            for (var i = 0; i < n; i++) {
                txt += (i > 0 ? "   " : "") + infos[i];
            }
            if (!tail.equals("")) { txt += (n > 0 ? "   " : "") + tail; }
            if (n == 0 || dc.getTextWidthInPixels(txt, Graphics.FONT_XTINY) <= room) { break; }
            n--;
        }
        dc.setColor(cInfo, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY, txt, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Anneau 24 h fixe pour aujourd'hui : minuit en haut, 6 h a droite, midi en bas, 18 h a gauche.
    // Heures passees eteintes, heures a venir colorees selon le vent.
    function drawRing(dc, cx, cy, u, off, dim) {
        var size = vals.size();
        var h0 = Gregorian.info(new Time.Moment(t0 + off * 3600), Time.FORMAT_SHORT).hour;
        var r = ((dim ? 166 : 164) * u).toNumber();
        var pen = ((dim ? 4 : 8) * u).toNumber();
        for (var h = 0; h < 24; h++) {
            var idx = off + h - h0;
            var c = PAST_COLOR;
            dc.setPenWidth(pen);
            if (lost) {
                // plus de prevision : tout le tour en gris, heures passees en trait fin comme d'habitude
                c = dim ? 0x444444 : lerpColor(0x000000, cStale, ringLevel);
                if (h < h0 && !dim) { dc.setPenWidth((3 * u).toNumber()); }
            } else if (h < h0 && !dim) {
                if (PAST_STYLE == 1) {
                    // vent passe en couleurs tres sombres
                    if (idx >= 0 && idx < size) {
                        c = lerpColor(0x000000, colors[band(vals[idx])], PAST_LEVEL);
                    }
                } else if (PAST_STYLE == 3) {
                    // trait fin, couleur du vent passe assombrie
                    if (idx >= 0 && idx < size) {
                        c = lerpColor(0x000000, colors[band(vals[idx])], 0.35);
                    }
                    dc.setPenWidth((3 * u).toNumber());
                } else {
                    // trait fin gris
                    c = 0x555555;
                    dc.setPenWidth((2 * u).toNumber());
                }
            } else if (h >= h0 && idx < size) {
                var b = band(vals[idx]);
                if (dim) {
                    if (b == 0) { continue; }
                    c = dimColors[b];
                } else {
                    c = lerpColor(0x000000, colors[b], ringLevel);
                }
            } else if (dim) {
                continue;
            }
            dc.setColor(c, Graphics.COLOR_TRANSPARENT);
            var st = (89 - 15 * h + 360) % 360;
            var en = (76 - 15 * h + 360) % 360;
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, st, en);
        }
        dc.setPenWidth(1);
        if (!dim) {
            drawRingLabels(dc, cx, cy, u, r);
        }
    }

    // Reperes 0, 6, 12, 18 dans des pastilles noires posees sur l'anneau
    function drawRingLabels(dc, cx, cy, u, r) {
        var labels = ["0", "6", "12", "18"];
        var rad = (11 * u).toNumber();
        // sans police vectorielle (fenix 6), la police systeme est plus haute : on rentre les
        // reperes juste assez pour qu'ils ne soient pas coupes par le bord de l'ecran
        var lr = r;
        if (!(Graphics has :getVectorFont)) {
            var maxR = dc.getWidth() / 2 - dc.getFontHeight(fontLabel) / 2;
            if (maxR < lr) { lr = maxR; }
        }
        for (var i = 0; i < 4; i++) {
            var a = Math.toRadians(i * 90.0);
            var x = cx + (lr * Math.sin(a)).toNumber();
            var y = cy - (lr * Math.cos(a)).toNumber();
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, rad);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, fontLabel, labels[i], Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Trait de l'heure actuelle sur l'anneau 24 h
    function drawNowTick(dc, cx, cy, u, clock) {
        var a = Math.toRadians((clock.hour + clock.min / 60.0) * 15.0);
        var sa = Math.sin(a);
        var ca = Math.cos(a);
        // couvre juste l'epaisseur de l'anneau (rayon 164, trait 8)
        var r1 = 158 * u;
        var r2 = 170 * u;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((4 * u).toNumber());
        dc.drawLine(cx + (r1 * sa).toNumber(), cy - (r1 * ca).toNumber(), cx + (r2 * sa).toNumber(), cy - (r2 * ca).toNumber());
        dc.setPenWidth(1);
    }

    function drawMain(dc, cx, cy, u, clock, off, n) {
        var info = Gregorian.info(new Time.Moment(t0 + off * 3600), Time.FORMAT_SHORT);
        var h0 = info.hour;
        var dow0 = info.day_of_week;

        drawRing(dc, cx, cy, u, off, false);
        drawNowTick(dc, cx, cy, u, clock);

        dc.setColor(cDate, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - ((small ? 104 : 120) * u).toNumber(), Graphics.FONT_XTINY, topDateText(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        if (!small) {
            drawTopLine(dc, cx, cy - (94 * u).toNumber(), nowSec());
        }

        // polices systeme (pas de police vectorielle) : chiffres plus hauts, on ecarte l'heure et la ligne vent
        var sysFont = !(Graphics has :getVectorFont);
        drawTimeLine(dc, cx, cy - ((sysFont ? 32 : 26) * u).toNumber(), fontMid, clock);

        if (lost) {
            // vent actuel et max trop anciens pour etre utiles : le message prend leur place
            drawLost(dc, cx, cy, u);
        } else {
            drawWindLine(dc, cx, cy + ((sysFont ? 28 : 25) * u).toNumber(), off, n, h0);

            drawChart(dc, cx, cy, u, off, n, h0, dow0);
        }
    }

    // Plus de prevision depuis LOST_AFTER : a la place du vent et de la courbe, depuis quand et quoi faire.
    // Sans code d'erreur, la requete n'est pas partie ou n'est pas revenue : le plus souvent
    // Garmin Connect est ferme ou endormi sur le telephone.
    function drawLost(dc, cx, cy, u) {
        var yb = cy + ((tiny ? 104 : 98) * u).toNumber();
        var hl = dc.getFontHeight(fontLabel);
        // en jours au-dela de 48 h : « 120 h » deborde sur les ecrans a grande police (vivoactive 5)
        var hours = (nowSec() - fetchedAt) / 3600;
        var age = hours < 48 ? hours.toString() + " h" : (hours / 24).toString() + " j";
        var title = small ? "Météo vieille de " + age : "Pas de prévision depuis " + age;
        var err = Application.Storage.getValue("err");
        // largeurs verifiees sur toutes les montres (data/font_metrics.json) : deux lignes courtes
        // tiennent dans le cercle, une seule longue ligne touchait l'anneau (petits ecrans : pas
        // de nom de spot en dessous, la place ne manque pas)
        var lines = ["ouvre Garmin Connect", "sur ton tél."];
        if (err != null && !(err < 0 && err > -300)) {
            lines = small ? ["météo injoignable"] : ["météo injoignable", "nouvel essai auto"];
        }
        var y = cy + (28 * u).toNumber();
        dc.setColor(cInfo, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, fontLoad, title, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        y += (dc.getFontHeight(fontLoad) - hl) / 2;
        dc.setColor(cSoft2, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < lines.size(); i++) {
            y += hl;
            dc.drawText(cx, y, fontLabel, lines[i], Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        drawSpot(dc, cx, yb + (36 * u).toNumber(), u);
    }

    // Une ligne : vent actuel en couleur, puis « · max 8 à 15h » en petit gris, alignes sur la ligne de base
    function drawWindLine(dc, cx, y, off, n, h0) {
        var cur = curVal;
        var curStr = knots(cur);
        var fBig = Graphics.FONT_XTINY;
        var fSmall = Graphics.FONT_XTINY;
        var w1 = dc.getTextWidthInPixels(curStr, fBig);
        var asc = Graphics.getFontAscent(fBig);
        // fleche de direction apres la vitesse (si connue)
        var dir = curDir;
        var gap = (dir >= 0) ? (asc * 0.25).toNumber() : 0;   // espace entre « nd » et la fleche
        var aw = (dir >= 0) ? (asc * 1.15).toNumber() : 0;
        // pic : format le plus complet qui tient dans le cercle a cette hauteur (la place depend
        // de la police de chaque montre, pas seulement de la taille d'ecran), sinon le plus court
        var u = dc.getWidth() / 340.0;
        var dy = (y - dc.getHeight() / 2).abs();
        var rIn = 156 * u;
        var room = (dy < rIn) ? (2 * Math.sqrt(rIn * rIn - dy * dy)).toNumber() : 0;
        var peaks = peakTexts(off, h0);
        var peakStr = "";
        var w2 = 0;
        for (var i = 0; i < peaks.size(); i++) {
            peakStr = " · " + peaks[i];
            w2 = dc.getTextWidthInPixels(peakStr, fSmall);
            if (w1 + gap + aw + w2 <= room) { break; }
        }
        var x = cx - (w1 + gap + aw + w2) / 2;
        var base = y + asc / 2;
        dc.setColor(stale ? cStale : windColor(cur), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, base - asc, fBig, curStr, Graphics.TEXT_JUSTIFY_LEFT);
        if (dir >= 0) {
            drawArrow(dc, x + w1 + gap + aw / 2, base - (asc * 0.36).toNumber(), (asc * 0.45), dir);
        }
        dc.setColor(cSoft, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w1 + gap + aw, base - Graphics.getFontAscent(fSmall), fSmall, peakStr, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // Fleche « ou va le vent » (dir = d'ou il vient, en degres), centree en (x, y), demi-longueur r :
    // tige + pointe triangulaire
    function drawArrow(dc, x, y, r, dir) {
        var a = Math.toRadians(dir + 180.0);
        var tx = Math.sin(a);       // sens de la fleche (ecran : y vers le bas)
        var ty = -Math.cos(a);
        var nx = -ty;               // perpendiculaire
        var ny = tx;
        var tipX = x + tx * r;
        var tipY = y + ty * r;
        var head = r * 0.75;
        var baseX = tipX - tx * head;
        var baseY = tipY - ty * head;
        dc.setPenWidth((r * 0.28).toNumber() < 2 ? 2 : (r * 0.28).toNumber());
        dc.drawLine((x - tx * r).toNumber(), (y - ty * r).toNumber(), baseX.toNumber(), baseY.toNumber());
        dc.setPenWidth(1);
        dc.fillPolygon([
            [tipX.toNumber(), tipY.toNumber()],
            [(baseX + nx * head * 0.6).toNumber(), (baseY + ny * head * 0.6).toNumber()],
            [(baseX - nx * head * 0.6).toNumber(), (baseY - ny * head * 0.6).toNumber()]
        ]);
    }

    // Pic de toute la journee (de minuit a minuit, heures passees comprises) ; a partir d'1 h
    // avant le coucher du soleil au spot, pic du lendemain avec le nom du jour.
    // Formats du plus complet au plus court (drawWindLine prend le premier qui tient) :
    // « max 18 nd 15h » puis « max 18 · 15h » ; « sam. 22 nd 15h » puis « sa 22 nd 15h ».
    // Le plus court tient sur les 113 montres (verifie avec tools/textwidth.py).
    function peakTexts(off, h0) {
        var day0 = off - h0;
        var tomorrow = (nowSec() >= sunsetAt() - 3600) && (day0 + 24 < vals.size());
        if (tomorrow) { day0 += 24; }
        var first = (day0 < 0) ? 0 : day0;
        var last = day0 + 24;
        if (last > vals.size()) { last = vals.size(); }
        var best = -1;
        var bestIdx = 0;
        for (var i = first; i < last; i++) {
            if (vals[i] > best) {
                best = vals[i];
                bestIdx = i;
            }
        }
        if (best < 0) { return []; }
        var v = ((best + 5) / 10).toString();
        var h = (bestIdx - day0).toString() + "h";
        if (tomorrow) {
            var dow = Gregorian.info(new Time.Moment(nowSec() + 86400), Time.FORMAT_SHORT).day_of_week - 1;
            return [DAYS[dow] + ". " + v + " nd " + h, DAYS2[dow] + " " + v + " nd " + h];
        }
        return ["max " + v + " nd " + h, "max " + v + " · " + h];
    }

    // Coucher du soleil au spot, aujourd'hui (secondes epoch), calcule une fois par jour et par spot
    var sunsetDay = -1;
    var sunsetLat = "";
    var sunsetVal = 0;
    function sunsetAt() {
        var now = nowSec();
        var day = (now + System.getClockTime().timeZoneOffset) / 86400;
        var c = spotCoords();
        var key = c[0].toString() + c[1].toString();
        if (day == sunsetDay && key.equals(sunsetLat)) { return sunsetVal; }
        sunsetVal = sunTime(c[0], c[1], now, false);
        sunsetDay = day;
        sunsetLat = key;
        return sunsetVal;
    }

    function drawChart(dc, cx, cy, u, off, n, h0, dow0) {
        var x0 = cx - ((tiny ? 97 : 110) * u).toNumber();
        var wTot = ((tiny ? 195 : 220) * u).toNumber();
        var yb = cy + ((tiny ? 104 : 98) * u).toNumber();
        // echelle automatique : haut du graphique = max de la periode (entre 16 et 28 nd)
        var vmax = 160;
        for (var i = 0; i < n; i++) {
            if (vals[off + i] > vmax) { vmax = vals[off + i]; }
        }
        if (vmax > CAP) { vmax = CAP; }
        var k = (48 * u) / vmax; // pixels par dixieme de noeud

        // colonnes colorees selon la tranche de chaque heure
        for (var i = 0; i < n; i++) {
            var tn = vals[off + i];
            if (tn > CAP) { tn = CAP; }
            var xl = x0 + (i * wTot) / n;
            var xr = x0 + ((i + 1) * wTot) / n;
            var wid = xr - xl;
            if (wid < 1) { wid = 1; }
            // colonne entiere dans la couleur de sa tranche
            var bi = band(tn);
            var yTop = yb - (tn * k).toNumber();
            dc.setColor(colors[bi], Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(xl, yTop, wid, yb - yTop);
        }

        // contour de la courbe
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var px = 0;
        var py = 0;
        for (var i = 0; i < n; i++) {
            var tn = vals[off + i];
            if (tn > CAP) { tn = CAP; }
            var xc = x0 + ((2 * i + 1) * wTot) / (2 * n);
            var yc = yb - (tn * k).toNumber();
            if (i > 0) {
                dc.drawLine(px, py, xc, yc);
            }
            px = xc;
            py = yc;
        }
        dc.setPenWidth(1);

        // ligne pointillee a 12 noeuds
        var y12 = yb - (120 * k).toNumber();
        dc.setColor(cLine, Graphics.COLOR_TRANSPARENT);
        for (var x = x0; x < x0 + wTot; x += 8) {
            dc.drawLine(x, y12, x + 4, y12);
        }
        // repere « 12 » au bout de la ligne pointillee (l'echelle est automatique). Sans police
        // vectorielle, il est ecrit dans la meme police que la ligne vent et se confond avec l'heure
        // du pic juste au-dessus (« 13h ») : il passe alors a gauche, au debut de la ligne.
        if (!tiny) {
            if (fontLabel == Graphics.FONT_XTINY) {
                dc.drawText(x0 - (3 * u).toNumber(), y12, fontLabel, "12", Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            } else {
                dc.drawText(x0 + wTot + (3 * u).toNumber(), y12, fontLabel, "12", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        }

        // separations de jours et noms des jours
        var start = 0;
        var yLab = yb + (15 * u).toNumber();
        var maxDx = (80 * u).toNumber();
        for (var i = 1; i <= n; i++) {
            if (i == n || (h0 + i) % 24 == 0) {
                if (i < n) {
                    var xs = x0 + (i * wTot) / n;
                    dc.setColor(cSep, Graphics.COLOR_TRANSPARENT);
                    dc.drawLine(xs, yb - (45 * u).toNumber(), xs, yb);
                }
                if (i - start >= 14) {
                    var center = x0 + ((start + i) * wTot) / (2 * n);
                    var dx = center - cx;
                    if (dx < 0) { dx = -dx; }
                    if (dx <= maxDx) {
                        var di = (dow0 - 1 + (h0 + start) / 24) % 7;
                        dc.setColor(cDays, Graphics.COLOR_TRANSPARENT);
                        dc.drawText(center, yLab, Graphics.FONT_XTINY, tiny ? DAYS1[di] : DAYS2[di], Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                    }
                }
                start = i;
            }
        }

        drawSpot(dc, cx, yb + (36 * u).toNumber(), u);

        // curseur sur l'heure courante
        var t0n = curVal;
        if (t0n > CAP) { t0n = CAP; }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(x0, yb - (48 * u).toNumber(), x0, yb);
        dc.setPenWidth(1);
        dc.fillCircle(x0, yb - (t0n * k).toNumber(), (4 * u).toNumber());
    }

    // Nom du spot en petit sous le graphique, precede d'une epingle de localisation
    function drawSpot(dc, cx, y, u) {
        if (small) { return; }
        var name = prop("curName", "");
        if (name == null || name.toString().equals("")) { name = prop("spotName", ""); }
        if (name == null || name.toString().equals("")) { return; }
        var pin = (10 * u).toNumber();
        var gap = (4 * u).toNumber();
        // largeur disponible a cette hauteur dans l'ecran rond (anneau compris), moins l'epingle
        var dy = (y - dc.getHeight() / 2).abs();
        var rIn = 150 * u;
        var maxW = (dy < rIn) ? (2 * Math.sqrt(rIn * rIn - dy * dy)).toNumber() - pin - gap : 0;
        name = fitName(dc, name.toString(), maxW);
        var w = dc.getTextWidthInPixels(name, fontLabel);
        var x = cx - (w + pin + gap) / 2;
        var pr = (pin / 2).toNumber();
        var pcx = x + pr;
        var pcy = y - (2 * u).toNumber();
        dc.setColor(cSoft, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(pcx, pcy, pr);
        dc.fillPolygon([[pcx - pr + 1, pcy + 1], [pcx + pr - 1, pcy + 1], [pcx, pcy + pr * 2]]);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(pcx, pcy, (pr / 2.5).toNumber());
        dc.setColor(cSoft, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + pin + gap, y, fontLabel, name, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Nom qui tient dans maxW : entier, sinon la partie avant « - » ou « , », sinon coupe avec « … »
    function fitName(dc, name, maxW) {
        if (dc.getTextWidthInPixels(name, fontLabel) <= maxW) { return name; }
        var sep = name.find(" - ");
        if (sep == null) { sep = name.find(", "); }
        if (sep != null && sep > 0) {
            name = name.substring(0, sep);
            if (dc.getTextWidthInPixels(name, fontLabel) <= maxW) { return name; }
        }
        while (name.length() > 1 && dc.getTextWidthInPixels(name + "…", fontLabel) > maxW) {
            name = name.substring(0, name.length() - 1);
        }
        return name + "…";
    }

    // Ecran sans donnees : meme mise en page que l'ecran principal (anneau vide, date, heure),
    // le message de chargement prend la place de la ligne vent et de la courbe
    function drawLoadingScreen(dc, cx, cy, u, clock) {
        var r = (164 * u).toNumber();
        dc.setPenWidth((8 * u).toNumber());
        // gris sombre sur AMOLED ; gris de la palette 64 couleurs sur MIP (sinon arrondi au noir)
        dc.setColor(amoled ? 0x262626 : 0x555555, Graphics.COLOR_TRANSPARENT);
        for (var h = 0; h < 24; h++) {
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, (89 - 15 * h + 360) % 360, (76 - 15 * h + 360) % 360);
        }
        dc.setPenWidth(1);
        drawRingLabels(dc, cx, cy, u, r);
        drawNowTick(dc, cx, cy, u, clock);

        dc.setColor(cDate, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - ((small ? 104 : 120) * u).toNumber(), Graphics.FONT_XTINY, topDateText(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        if (!small) {
            drawTopLine(dc, cx, cy - (94 * u).toNumber(), nowSec());
        }
        drawTimeLine(dc, cx, cy - (26 * u).toNumber(), fontMid, clock);
        drawLoading(dc, cx, cy + (44 * u).toNumber());
    }

    // Pas encore de donnees (premier lancement ou changement de spot) : la prevision arrive
    // a la prochaine requete d'arriere-plan, au plus tot 5 min apres la precedente
    function drawLoading(dc, cx, y) {
        var u = dc.getWidth() / 340.0;
        var hx = dc.getFontHeight(fontLoad);
        var hl = dc.getFontHeight(fontLabel);
        // derniere requete en echec : on dit pourquoi au lieu de « Chargement… »
        var err = Application.Storage.getValue("err");
        var title = small ? "Chargement…" : "Chargement des prévisions…";
        var lines = small ? ["sous 5 min", "téléphone à côté"] : ["sous 5 min · téléphone", "Bluetooth à côté"];
        if (err != null) {
            // codes Garmin -1 a -299 : liaison Bluetooth avec le telephone ; le reste : reseau ou service meteo
            var ble = err < 0 && err > -300;
            if (ble) {
                title = small ? "Pas de téléphone" : "Téléphone non connecté";
                lines = small ? ["Bluetooth ?", "essai auto · " + err] : ["Bluetooth et Garmin Connect", "nouvel essai auto · " + err];
            } else {
                title = small ? "Météo indisponible" : "Prévisions indisponibles";
                lines = small ? ["service injoignable", "essai auto · " + err] : ["service météo injoignable", "nouvel essai auto · " + err];
            }
        }
        dc.setColor(cInfo, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, fontLoad, title, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        // le spot est a sa place definitive, sous la courbe (graphique : yb = 98u, spot a yb + 36u)
        drawSpot(dc, cx, dc.getHeight() / 2 + (134 * u).toNumber(), u);
        y += (hx - hl) / 2;
        for (var i = 0; i < lines.size(); i++) {
            y += hl;
            dc.setColor(cSoft2, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, fontLabel, lines[i], Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Veille (always-on) : peu de pixels allumes, decalage leger anti marquage
    function drawSleep(dc, cx, cy, u, clock, off, n) {
        var ox = ((clock.min % 5) - 2) * 2;
        var oy = (((clock.min / 5) % 5) - 2) * 2;
        if (n > 0) {
            drawRing(dc, cx, cy, u, off, true);
        }
        // heure a la meme taille que l'ecran principal, en gris (AMOLED recents, limite en luminance) ;
        // police moyenne sur les anciens AMOLED sans police vectorielle (Venu 1...) : limite en pixels allumes
        var big = (Graphics has :getVectorFont);
        dc.setColor(0x8A8880, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + ox, cy - ((big ? 26 : 10) * u).toNumber() + oy, big ? fontMid : Graphics.FONT_NUMBER_MEDIUM, timeString(clock), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(0x6B6A64, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + ox, cy + (40 * u).toNumber() + oy, Graphics.FONT_XTINY, topDateText(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        if (n > 0 && !lost) {
            dc.setColor(stale ? cStale : windColor(curVal), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + ox, cy + (68 * u).toNumber() + oy, Graphics.FONT_XTINY, knots(curVal), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        if (!big) {
            // anciens AMOLED (regle : aucun pixel allume plus de 3 min) : une ligne sur deux eteinte,
            // en alternant chaque minute, donc chaque pixel s'eteint au moins une minute sur deux
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            var w = dc.getWidth();
            for (var yy = clock.min % 2; yy < dc.getHeight(); yy += 2) {
                dc.drawLine(0, yy, w, yy);
            }
        }
    }
}

// Horloge figee pour le mode test (memes champs que System.ClockTime)
class TestClock {
    var hour;
    var min;

    function initialize(h, m) {
        hour = h;
        min = m;
    }
}
