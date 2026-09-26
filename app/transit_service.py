# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import json
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

from . import brand

BASE = "https://api.transitous.org/api/v1/"
HEADERS = {"User-Agent": f"{brand.NAME}/0.4 (Schul-App)", "Accept": "application/json"}
MAX_CACHE = 400

_cache = {}
_lock = threading.Lock()

CATEGORIES = {
    "HIGHSPEED_RAIL": "fern",
    "LONG_DISTANCE": "fern",
    "NIGHT_RAIL": "fern",
    "COACH": "fernbus",
    "REGIONAL_FAST_RAIL": "regio",
    "REGIONAL_RAIL": "regio",
    "RAIL": "regio",
    "SUBURBAN": "sbahn",
    "METRO": "sbahn",
    "SUBWAY": "ubahn",
    "TRAM": "tram",
    "BUS": "bus",
    "FERRY": "faehre",
    "WALK": "fuss",
    "BIKE": "rad",
}
LONG_DISTANCE = {"fern", "fernbus"}


def _arg(args, key, limit=120):
    value = args.get(key)
    if value is None:
        return None
    return str(value).strip()[:limit]


def fetch(path, params, ttl):
    query = urllib.parse.urlencode({key: value for key, value in params.items() if value not in (None, "")})
    url = f"{BASE}{path}?{query}"
    with _lock:
        hit = _cache.get(url)
    if hit and time.time() - hit[0] < ttl:
        return hit[1]
    request = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(request, timeout=12) as response:
        data = json.load(response)
    with _lock:
        _cache[url] = (time.time(), data)
        if len(_cache) > MAX_CACHE:
            for key in sorted(_cache, key=lambda item: _cache[item][0])[:100]:
                _cache.pop(key, None)
    return data


def category(mode):
    return CATEGORIES.get(mode or "", "sonst")


def line_name(item):
    name = (item.get("routeShortName") or item.get("displayName") or "").strip()
    if "(" in name and name.endswith(")"):
        name = name[: name.rfind("(")].strip()
    return name


def area_of(item):
    areas = item.get("areas") or []
    preferred = next((area for area in areas if area.get("default")), None) or next((area for area in areas if area.get("matched")), None)
    return (preferred or {}).get("name", "")


def search(args):
    text = _arg(args, "q", 80) or ""
    if len(text) < 2:
        return {"places": []}, 200
    near = _arg(args, "nahe", 60) or None
    bias = _arg(args, "bias", 4) or ("5" if near else None)
    data = fetch("geocode", {"text": text, "language": "de", "place": near, "placeBias": bias}, 3600)
    places = []
    for item in data:
        kind = {"STOP": "stop", "ADDRESS": "address"}.get(item.get("type"), "place")
        if item.get("country") not in (None, "DE") and kind != "stop":
            continue
        place = item.get("id") if kind == "stop" else f"{item.get('lat')},{item.get('lon')}"
        places.append({
            "id": place,
            "name": item.get("name", ""),
            "area": area_of(item),
            "kind": kind,
            "modes": sorted({category(mode) for mode in item.get("modes") or []}),
            "lat": item.get("lat"),
            "lon": item.get("lon"),
        })
    return {"places": places[:8]}, 200


def departures(args):
    stop = _arg(args, "stop")
    if not stop:
        return {"error": "Haltestelle fehlt"}, 400
    try:
        count = max(1, min(int(args.get("n", 14)), 30))
    except (TypeError, ValueError):
        count = 14
    data = fetch("stoptimes", {"stopId": stop, "n": count, "time": _arg(args, "zeit", 40)}, 30)
    seen = {}
    for item in data.get("stopTimes", []):
        place = item.get("place", {})
        planned = place.get("scheduledDeparture") or place.get("departure")
        key = (category(item.get("mode")), line_name(item), planned)
        entry = {
            "line": line_name(item),
            "category": category(item.get("mode")),
            "direction": item.get("headsign") or (item.get("tripTo") or {}).get("name", ""),
            "planned": planned,
            "time": place.get("departure") or planned,
            "track": place.get("track") or place.get("scheduledTrack"),
            "cancelled": bool(item.get("cancelled") or item.get("tripCancelled")),
            "realtime": bool(item.get("realTime")),
        }
        current = seen.get(key)
        if not current or (entry["realtime"] and not current["realtime"]) or (entry["track"] and not current["track"]):
            seen[key] = entry
    stop_name = (data.get("place") or {}).get("name", "")
    items = sorted(seen.values(), key=lambda entry: entry["time"] or "")
    return {"stop": stop_name, "departures": items}, 200


def leg_view(leg):
    origin = leg.get("from", {})
    target = leg.get("to", {})
    return {
        "category": category(leg.get("mode")),
        "line": line_name(leg),
        "headsign": leg.get("headsign") or "",
        "agency": leg.get("agencyName") or "",
        "from": {"name": origin.get("name", ""), "time": leg.get("startTime"), "planned": leg.get("scheduledStartTime"), "track": origin.get("track") or origin.get("scheduledTrack")},
        "to": {"name": target.get("name", ""), "time": leg.get("endTime"), "planned": leg.get("scheduledEndTime"), "track": target.get("track") or target.get("scheduledTrack")},
        "minutes": round((leg.get("duration") or 0) / 60),
        "distance": round(leg.get("distance") or 0),
        "stops": len(leg.get("intermediateStops") or []),
        "realtime": bool(leg.get("realTime")),
        "cancelled": bool(leg.get("cancelled")),
    }


def journeys(args):
    origin, target = _arg(args, "von"), _arg(args, "nach")
    if not origin or not target:
        return {"error": "Start oder Ziel fehlt"}, 400
    params = {
        "fromPlace": origin,
        "toPlace": target,
        "time": _arg(args, "zeit", 40),
        "arriveBy": "true" if args.get("ankunft") == "1" else "false",
        "numItineraries": 5,
    }
    data = fetch("plan", params, 45)
    result = []
    for item in data.get("itineraries", []):
        legs = [leg_view(leg) for leg in item.get("legs", [])]
        rides = [leg for leg in legs if leg["category"] not in ("fuss", "rad")]
        if not legs:
            continue
        ticket = "fuss" if not rides else "fern" if any(leg["category"] in LONG_DISTANCE for leg in rides) else "deutschland"
        result.append({
            "start": item.get("startTime"),
            "end": item.get("endTime"),
            "minutes": round((item.get("duration") or 0) / 60),
            "transfers": item.get("transfers", max(0, len(rides) - 1)),
            "legs": legs,
            "ticket": ticket,
            "realtime": any(leg["realtime"] for leg in rides),
            "cancelled": any(leg["cancelled"] for leg in rides),
        })
    return {"journeys": result}, 200


def nearby(args):
    try:
        lat, lon = float(args.get("lat")), float(args.get("lon"))
    except (TypeError, ValueError):
        return {"error": "Standort fehlt"}, 400
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return {"error": "Standort fehlt"}, 400
    span = 0.006
    data = fetch("map/stops", {"min": f"{lat - span},{lon - span}", "max": f"{lat + span},{lon + span}"}, 300)
    stops = [{"id": item.get("stopId"), "name": item.get("name", ""), "lat": item.get("lat"), "lon": item.get("lon")} for item in data if item.get("stopId")]
    stops.sort(key=lambda stop: (stop["lat"] - lat) ** 2 + (stop["lon"] - lon) ** 2)
    unique = {}
    for stop in stops:
        unique.setdefault(stop["name"], stop)
    return {"stops": list(unique.values())[:6]}, 200


ACTIONS = {"suche": search, "abfahrten": departures, "verbindungen": journeys, "naehe": nearby}


def handle(action, args):
    handler = ACTIONS.get(action)
    if not handler:
        return {"error": "unbekannt"}, 404
    try:
        return handler(args)
    except urllib.error.HTTPError as error:
        return {"error": f"Fahrplan antwortet mit {error.code}"}, 502
    except (urllib.error.URLError, TimeoutError, OSError):
        return {"error": "Fahrplan gerade nicht erreichbar"}, 504
    except (ValueError, KeyError, TypeError, AttributeError):
        return {"error": "Unerwartete Antwort vom Fahrplan"}, 502
