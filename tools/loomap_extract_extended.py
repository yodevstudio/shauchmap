import requests
import json
import time
import os

# State-by-state scoping keeps the Overpass server from exhausting its RAM.
STATES = [
    "Andhra Pradesh", "Arunachal Pradesh", "Assam", "Bihar", "Chhattisgarh",
    "Goa", "Gujarat", "Haryana", "Himachal Pradesh", "Jharkhand", "Karnataka",
    "Kerala", "Madhya Pradesh", "Maharashtra", "Manipur", "Meghalaya", "Mizoram",
    "Nagaland", "Odisha", "Punjab", "Rajasthan", "Sikkim", "Tamil Nadu",
    "Telangana", "Tripura", "Uttar Pradesh", "Uttarakhand", "West Bengal",
    "Andaman and Nicobar Islands", "Chandigarh", "Dadra and Nagar Haveli and Daman and Diu",
    "Delhi", "Jammu and Kashmir", "Ladakh", "Lakshadweep", "Puducherry"
]

OUTPUT_FILE = "loomap_extended_data.json"

def get_with_retries(query, state_name, max_retries=5):
    url = "http://overpass-api.de/api/interpreter"
    headers = {'User-Agent': 'LooMapApp Data Extractor - Non-Commercial/Educational'}
    for attempt in range(max_retries):
        try:
            response = requests.post(url, data={'data': query}, headers=headers, timeout=950)
            if response.status_code == 429:
                sleep_time = 60 * (attempt + 1)
                print(f"Rate limited on {state_name}. Cooling down {sleep_time}s...")
                time.sleep(sleep_time)
                continue
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"[Attempt {attempt + 1}/{max_retries}] Network issue on {state_name}: {e}")
            time.sleep(20)
        except json.JSONDecodeError:
            print(f"[Attempt {attempt + 1}/{max_retries}] Server overloaded (HTML not JSON). Retrying...")
            time.sleep(30)
    print(f"Skipped {state_name} permanently after {max_retries} attempts.")
    return None

def extract_all_india():
    all_places = []
    if os.path.exists(OUTPUT_FILE):
        try:
            with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
                all_places = json.load(f)
                print(f"Found existing file. Loaded {len(all_places)} points to resume.")
        except Exception:
            print("Existing file corrupted/empty. Restarting from scratch.")
            all_places = []

    existing_keys = {t['osm_id'] for t in all_places if 'osm_id' in t}
    print("Starting extended extraction (toilets + petrol pumps + malls)...")

    for state in STATES:
        print(f"\nProcessing: {state} ...")
        # Real toilets + the two DEFENSIBLE semi-public types only:
        #  - petrol pumps (legally mandated free public toilet access)
        #  - malls (reliably have free public restrooms)
        # Hospitals/transit deliberately EXCLUDED: access is uncertain; false promises kill trust.
        query = f"""
        [out:json][timeout:900];
        area["name"="{state}"]->.a;
        (
          node["amenity"="toilets"](area.a);
          way["amenity"="toilets"](area.a);
          relation["amenity"="toilets"](area.a);
          node["name"~"SBM|Sulabh|Toilet|Washroom|Restroom|Mootraalay|Swachh|MCD|BMC|e-Toilet|Urinal",i](area.a);
          way["name"~"SBM|Sulabh|Toilet|Washroom|Restroom|Mootraalay|Swachh|MCD|BMC|e-Toilet|Urinal",i](area.a);
          relation["name"~"SBM|Sulabh|Toilet|Washroom|Restroom|Mootraalay|Swachh|MCD|BMC|e-Toilet|Urinal",i](area.a);
          node["amenity"="fuel"](area.a);
          way["amenity"="fuel"](area.a);
          node["shop"="mall"](area.a);
          way["shop"="mall"](area.a);
        );
        out center;
        """
        data = get_with_retries(query, state)
        if not data:
            continue

        state_count = 0
        for element in data.get('elements', []):
            global_id = f"{element.get('type', 'node')}_{element.get('id')}"
            if global_id in existing_keys:
                continue
            try:
                lat = float(element.get('lat') or element.get('center', {}).get('lat'))
                lon = float(element.get('lon') or element.get('center', {}).get('lon'))
            except (ValueError, TypeError):
                continue

            tags = element.get('tags', {})
            amenity = tags.get('amenity', '')
            shop = tags.get('shop', '')
            raw_name = tags.get('name', '').strip()

            # --- Classify into the EXACT categories the app already renders ---
            # App understands: 'govt', 'petrol', 'mall', 'other'.
            if amenity == 'fuel':
                category = 'petrol'
                needs_confirm = True
                brand = tags.get('brand', '').strip()
                if not raw_name:
                    raw_name = f"{brand} Petrol Pump" if brand else "Petrol Pump"
            elif shop == 'mall':
                category = 'mall'
                needs_confirm = True
                if not raw_name:
                    raw_name = "Shopping Mall"
            else:
                # An actual mapped toilet.
                category = 'govt'
                needs_confirm = False
                if not raw_name:
                    operator = tags.get('operator', '').strip()
                    raw_name = f"{operator} Public Toilet" if operator else "Public Toilet"

            female, male = tags.get('female'), tags.get('male')
            gender = "unisex"
            if female == 'yes' and male != 'yes':
                gender = "female"
            elif male == 'yes' and female != 'yes':
                gender = "male"

            place = {
                "osm_id": global_id,
                "name": raw_name,
                "address": f"{state}, India",
                "latitude": lat,
                "longitude": lon,
                "category": category,            # <-- matches app (was wrongly "type" before)
                "needs_confirm": needs_confirm,  # <-- petrol/mall = inferred, not verified
                "is_free": tags.get('fee') == 'no' or category in ('petrol', 'mall') or tags.get('charge') is None,
                "is_wheelchair": tags.get('wheelchair') == 'yes',
                "has_water": tags.get('toilets:handwashing') == 'yes' or tags.get('water_point') == 'yes' or category == 'mall',
                "has_soap": False,
                "has_baby_change": tags.get('diaper') == 'yes' or tags.get('changing_table') == 'yes',
                "gender_type": gender,
            }
            all_places.append(place)
            existing_keys.add(global_id)
            state_count += 1

        print(f"Extracted {state_count} from {state}")

        temp_file = OUTPUT_FILE + ".tmp"
        try:
            with open(temp_file, 'w', encoding='utf-8') as f:
                json.dump(all_places, f, indent=2, ensure_ascii=False)
            os.replace(temp_file, OUTPUT_FILE)
        except Exception as e:
            print(f"Write warning: {e}")
        time.sleep(15)

    print(f"\nDONE. {len(all_places)} records in {OUTPUT_FILE}")

if __name__ == "__main__":
    extract_all_india()
