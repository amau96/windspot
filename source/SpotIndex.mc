// Genere par data/build_tree.py : ne pas modifier a la main.
import Toybox.Lang;
import Toybox.WatchUi;

// Liste des spots d'un departement (index n du fichier spots_index.json)
function spotGroupResource(n as Number) as ResourceId {
    var all = [
        Rez.JsonData.Spots0,
        Rez.JsonData.Spots1,
        Rez.JsonData.Spots2,
        Rez.JsonData.Spots3,
        Rez.JsonData.Spots4,
        Rez.JsonData.Spots5,
        Rez.JsonData.Spots6,
        Rez.JsonData.Spots7,
        Rez.JsonData.Spots8,
        Rez.JsonData.Spots9,
        Rez.JsonData.Spots10,
        Rez.JsonData.Spots11,
        Rez.JsonData.Spots12,
        Rez.JsonData.Spots13,
        Rez.JsonData.Spots14,
        Rez.JsonData.Spots15,
        Rez.JsonData.Spots16,
        Rez.JsonData.Spots17,
        Rez.JsonData.Spots18,
        Rez.JsonData.Spots19
    ];
    return all[n];
}

const SPOT_GROUP_COUNT = 20;
