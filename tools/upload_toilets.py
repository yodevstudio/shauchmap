import json
import os
import time
import firebase_admin
from firebase_admin import credentials, firestore
import pygeohash as pgh
from google.cloud.firestore_v1 import GeoPoint

SERVICE_ACCOUNT = 'tools/service-account.json'
DATA_FILE = 'tools/swachh_bharat_data_full.json'
COLLECTION = 'toilets'
BATCH_SIZE = 400

def main():
    if not os.path.exists(SERVICE_ACCOUNT):
        print('ERROR: tools/service-account.json not found')
        return
    if not os.path.exists(DATA_FILE):
        print('ERROR: tools/swachh_bharat_data_full.json not found')
        return

    cred = credentials.Certificate(SERVICE_ACCOUNT)
    firebase_admin.initialize_app(cred)
    db = firestore.client()

    with open(DATA_FILE, 'r', encoding='utf-8') as f:
        records = json.load(f)

    print(f'Loaded {len(records)} records. Starting upload...')

    junk_names = {'test', 'asdf', 'dummy', 'null', 'none', 'na', 'n/a', ''}
    uploaded = 0
    skipped = 0
    batch = db.batch()
    batch_count = 0

    for record in records:
        osm_id = str(record.get('osm_id', '')).strip()
        lat = record.get('latitude')
        lon = record.get('longitude')
        name = str(record.get('name', '')).strip()

        if not osm_id:
            skipped += 1
            continue
        if not lat or not lon or (lat == 0.0 and lon == 0.0):
            skipped += 1
            continue
        if lat < 6.0 or lat > 38.0 or lon < 68.0 or lon > 98.0:
            skipped += 1
            continue
        if name.lower() in junk_names or len(name) < 3:
            skipped += 1
            continue

        geohash = pgh.encode(lat, lon, precision=9)

        doc_data = {
            'osm_id': osm_id,
            'name': name if name else 'Public Toilet',
            'address': str(record.get('address', 'India')),
            'latitude': lat,
            'longitude': lon,
            'category': 'govt',
            'star_rating': 0.0,
            'total_ratings': 0,
            'is_open': True,
            'is_free': bool(record.get('is_free', True)),
            'gender_type': str(record.get('gender_type', 'unisex')),
            'has_water': bool(record.get('has_water', False)),
            'has_soap': False,
            'has_lock': False,
            'is_wheelchair': bool(record.get('is_wheelchair', False)),
            'has_baby_change': bool(record.get('has_baby_change', False)),
            'added_by': 'osm_india_import_2026',
            'landmark': '',
            'position': {
                'geopoint': GeoPoint(lat, lon),
                'geohash': geohash,
            },
        }

        doc_ref = db.collection(COLLECTION).document(osm_id)
        batch.set(doc_ref, doc_data)
        batch_count += 1
        uploaded += 1

        if batch_count >= BATCH_SIZE:
            batch.commit()
            print(f'  Uploaded {uploaded} records so far...')
            batch = db.batch()
            batch_count = 0
            time.sleep(0.5)

    if batch_count > 0:
        batch.commit()

    print(f'\nDONE. Uploaded: {uploaded}  Skipped: {skipped}')

if __name__ == '__main__':
    main()