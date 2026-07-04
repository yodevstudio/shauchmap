import requests
import json
import time
import os

# Scoping state-by-state prevents the Overpass API server from blowing up its RAM allocation
STATES = [
    "Andhra Pradesh", "Arunachal Pradesh", "Assam", "Bihar", "Chhattisgarh",
    "Goa", "Gujarat", "Haryana", "Himachal Pradesh", "Jharkhand", "Karnataka",
    "Kerala", "Madhya Pradesh", "Maharashtra", "Manipur", "Meghalaya", "Mizoram",
    "Nagaland", "Odisha", "Punjab", "Rajasthan", "Sikkim", "Tamil Nadu",
    "Telangana", "Tripura", "Uttar Pradesh", "Uttarakhand", "West Bengal",
    "Andaman and Nicobar Islands", "Chandigarh", "Dadra and Nagar Haveli and Daman and Diu",
    "Delhi", "Jammu and Kashmir", "Ladakh", "Lakshadweep", "Puducherry"
]

OUTPUT_FILE = "swachh_bharat_data_full.json"

def get_with_retries(query, state_name, max_retries=5):
    """Handles network drops, rate limits (HTTP 429), and HTML server-overload responses."""
    url = "http://overpass-api.de/api/interpreter"

    # Set a custom User-Agent so the server knows we aren't malicious spam
    headers = {
        'User-Agent': 'LooMapApp Data Extractor - Non-Commercial/Educational'
    }
    
    for attempt in range(max_retries):
        try:
            # High 950s timeout to allow heavy states (UP, Maharashtra) to finish regex sorting
            response = requests.post(url, data={'data': query}, headers=headers, timeout=950)
            
            if response.status_code == 429:
                sleep_time = 60 * (attempt + 1)
                print(f"⚠️ Rate limited on {state_name}. Cooling down for {sleep_time}s...")
                time.sleep(sleep_time)
                continue
                
            response.raise_for_status()
            
            # Catching raw HTML errors masked as status 200 OK
            return response.json()
            
        except requests.exceptions.RequestException as e:
            print(f"⚠️ [Attempt {attempt + 1}/{max_retries}] Network issue on {state_name}: {e}")
            time.sleep(20)
        except json.JSONDecodeError:
            print(f"⚠️ [Attempt {attempt + 1}/{max_retries}] Server overloaded (Returned HTML instead of JSON). Retrying...")
            time.sleep(30)
            
    print(f"❌ Skipped {state_name} permanently after {max_retries} failed attempts.")
    return None

def extract_all_india():
    all_toilets = []
    
    # Fault-tolerant resume block
    if os.path.exists(OUTPUT_FILE):
        try:
            with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
                all_toilets = json.load(f)
                print(f"📥 Found existing file. Loaded {len(all_toilets)} points to resume.")
        except Exception:
            print("⚠️ Existing file was corrupted or empty. Restarting pipeline from scratch.")
            all_toilets = []
            
    # Track unique global compound keys to avoid double-counting if restarted mid-way
    existing_keys = {t['osm_id'] for t in all_toilets if 'osm_id' in t}

    print("🚀 Starting Production-Grade Subcontinent Pipeline...")

    for state in STATES:
        print(f"\n⏳ Processing: {state} ...")
        
        # Robust name query capturing localized naming conventions and municipal variations
        # Evaluates node, way, and relation across all variations to capture large complexes
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
        );
        out center;
        """
        
        data = get_with_retries(query, state)
        if not data:
            continue
            
        state_count = 0
        for element in data.get('elements', []):
            # Compound Key prevents namespace collision between Node 123 and Way 123
            global_id = f"{element.get('type', 'node')}_{element.get('id')}"
            
            if global_id in existing_keys:
                continue
                
            # Geometry Verification
            try:
                lat = float(element.get('lat') or element.get('center', {}).get('lat'))
                lon = float(element.get('lon') or element.get('center', {}).get('lon'))
            except (ValueError, TypeError):
                continue  # Drops coordinates malformed by string truncations
                
            tags = element.get('tags', {})
            
            # Fallback Naming Hierarchy
            raw_name = tags.get('name', '').strip()
            if not raw_name:
                operator = tags.get('operator', '').strip()
                raw_name = f"{operator} Public Toilet" if operator else "Public Toilet"
            
            # Non-strict Inclusive Gender Logic
            female = tags.get('female')
            male = tags.get('male')
            gender = "unisex"
            if female == 'yes' and male != 'yes':
                gender = "female"
            elif male == 'yes' and female != 'yes':
                gender = "male"
                
            # Metadata Normalization matching your exact Flutter data model requirements
            toilet_data = {
                "osm_id": global_id,
                "name": raw_name,
                "address": f"{state}, India",
                "latitude": lat,
                "longitude": lon,
                "type": "community",
                "is_free": tags.get('fee') == 'no' or tags.get('charge') is None,
                "is_wheelchair": tags.get('wheelchair') == 'yes',
                "has_water": tags.get('toilets:handwashing') == 'yes' or tags.get('water_point') == 'yes',
                "has_soap": False,
                "has_baby_change": tags.get('diaper') == 'yes' or tags.get('changing_table') == 'yes',
                "gender_type": gender
            }
            
            all_toilets.append(toilet_data)
            existing_keys.add(global_id)
            state_count += 1
            
        print(f"✅ Extracted {state_count} clean objects from {state}")
        
        # Atomic Write-and-Swap File Save Strategy
        # Prevents files from getting instantly wiped to 0 bytes if a power/internet cut happens mid-save
        temp_file = OUTPUT_FILE + ".tmp"
        try:
            with open(temp_file, 'w', encoding='utf-8') as f:
                json.dump(all_toilets, f, indent=2, ensure_ascii=False)
            os.replace(temp_file, OUTPUT_FILE)
        except Exception as e:
            print(f"⚠️ Write warning: Could not save progress temporary file safely: {e}")
            
        # Standard safety delay prevents the Overpass endpoint from firewall-blocking your IP
        time.sleep(15)

    print(f"\n🎉 DATA EXTRACTION COMPLETE! {len(all_toilets)} records compiled cleanly inside {OUTPUT_FILE}")

if __name__ == "__main__":
    extract_all_india()