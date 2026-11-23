// Real photographs for seeded data.
//
// `npm run seed` downloads a small curated set of freely licensed photos from Wikimedia Commons
// (no API key) into backend/uploads/photo-<topic>-<n>.jpg, scaled to about 800 px wide by the
// Commons thumbnailer. Files already on disk are reused, so re-seeding is fast and works offline.
// When a download fails (offline, rate limited) the seed falls back to the generated PNGs.
import fs from 'node:fs';
import path from 'node:path';
import { UPLOAD_DIR } from './media.js';

const UA = 'ByThePeopleDemoSeed/1.0 (local demo data; contact: none)';
const WIDTH = 800;
const PER_TOPIC = 3;

// topic -> Commons file names (first PER_TOPIC that download are kept)
export const PHOTO_SETS = {
  pothole: ['Potholes on road.jpg', 'Potholed road outside Kolkata Airport.jpg', 'Roads in Bihar have potholes.jpg', 'Broken Roads in India\'s Capital New Delhi.jpg', 'Roads deformed T munnekollala Bengaluru.jpg'],
  garbage: ['India - Sights & Culture - Common garbage dump outside a temple (2566331277).jpg', 'Hyderabad Street Garbage collection 2005.jpg', 'Garbage Disposal Hyderabad 2005.jpg', 'KolkataTrash.JPG', 'A burning roadside garbage dump at Panvel Naka near Mumbai.jpg'],
  water: ['Water tanker refilling in Bengaluru.jpg', 'Wong Chuk Hang Road water pipe burst 24-08-2023.jpg', 'Burst water pipe - geograph.org.uk - 6866868.jpg', 'Burst pipe in Hill Road - geograph.org.uk - 2946389.jpg'],
  drainage: ['India - Chennai - Monsoon - 05 (3058218683).jpg', 'India - Chennai - Monsoon - 04 (3058215637).jpg', 'India - Chennai - Monsoon - 03 (3058213357).jpg', 'India - Chennai - Monsoon - 09 (3058285493).jpg'],
  streetlight: ['2023-08-31 20 35 00 LED street light at night on utility pole 64879EW along Lochatong Road in the Mountainview section of Ewing Township, Mercer County, New Jersey.jpg', 'Street light next to a birch.jpg', 'A lamp post at City Palace, Udaipur City, Rajasthan State, India.jpg', '2014-12-26 16 58 08 Mercury vapor street light just after turning on for the night on Terrace Boulevard in Ewing, New Jersey.JPG'],
  electricity: ['TNEB Transformer Kulisholai Sep25 A7CR 07592.jpg'],
  park: ['Changampuzha playground area.jpg', 'Malampuzha Garden Childrens Park 1.JPG', 'Playground swing 01.jpg', 'A Children Park in Hokenakal.JPG', 'Playground swing 03.jpg'],
  market: ['Vegetable market, Ahmedabad.jpg', 'Vegetable market Hyderabad.jpg', 'Goa, India. A vegetable vendor in the market 01.jpg'],
  plantation: ['DUSAFO planting trees.jpg', 'Volunteers carry trees to planting sites (37287300136).jpg', 'Chicago Burnham Corridor Volunteers planting (13984713420).jpg'],
  cleanup: ['Smithville Lake Cleanup Day (8020863131).jpg', 'Smithville Lake Cleanup Day (8020876786).jpg', 'Smithville Lake Cleanup Day (8020873151).jpg', 'Smithville Lake Cleanup Day (8020882186).jpg'],
  marathon: ['Indian military men at a marathon in Goa, India. March 2015.JPG', '2008 Pune Marathon runners.jpg', 'African (Ethiopian) marathon winner in Goa, India. March 2015..JPG', 'Dharampal singh gudha after finishing his race.jpg'],
  animal: ['Stray dogs from Kozhikode, Kerala, India.jpg', 'Stray Dog - Kolkata 05907.JPG', 'Khajuraho - stray dog.jpg', 'Stray dog feeding her puppies in a rural courtyard.jpg'],
  blood: ['Blood donation camp at Kelvin.jpg', 'Blood donation camp by sudheekshan foundation.jpg', 'Blood Donation Camp on Navy Day 2015 (01).jpg', 'Blood Donation Camp - Baranagar Mission.jpg'],
  food: ['Distribution of Food from Street Kitchen - Amritsar - Punjab - India (12675516265).jpg', 'Free community kitchen, daana volunteer run daily dining hall Annapurna Hindu temple Mudbidri Karnataka India.jpg', 'Indian Navy personnel preparing food at a community kitchen in the aftermath of Cyclone Hudhud.JPG', 'Community Kitchen in a village panchayat.jpg'],
  thali: ['Darjeeling, India, Indian Thali meal.jpg', '\'5\' A vegetarian thali, traditional style of serving a meal in India.jpg', '\'0\' A thali, meal served in India.jpg', 'Thali meal-Before.jpg'],
  clothes: ['Red Cross clothes donation bin in Berlin.jpg', 'Clothes donation containers, Vancouver Mall, Vancouver, WA, March 2020.jpg', 'Salvation Army clothes ^ shoes donation bin, Oakengates - geograph.org.uk - 4796479.jpg'],
  books: ['Global Open Initiative Foundation donates books to Madina Institute of Science and TechnologyDSC1379.jpg', 'Global Open Initiative Foundation donates books to Madina Institute of Science and Technology DSC1381.jpg', 'Donated books arriving at Kamiti Prison.JPG'],
  toys: ['A Photo of Toys Donated by State Department Employees (46212820822).jpg', 'NATO soldiers donate toys to Polish foster children (6965498).jpg'],
  shelter: ['Urban Homeless Shelter Centre Buildin,Municipal Council Nalgonda.jpg', 'Homeless children 1.jpg'],
  ngo: ['EVidyaloka Rubaru 2018-1.jpg', 'Femina Miss India Contestants visit NGO children (25).jpg', 'Femina Miss India Contestants visit NGO children (17).jpg'],
  health: ['RGJAY health camp Faizpur 4.jpg', 'RGJAY health camp Faizpur 2.jpg', 'FREE HEALTH CAMP IN URBAN HEALTH CENTRE OF IMA, TIRUPATI.jpg'],
};

const fileFor = (topic, n) => `photo-${topic}-${n}.jpg`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Photo URLs (/uploads/...) already on disk for a topic. */
export function photosFor(topic) {
  const out = [];
  for (let n = 1; n <= PER_TOPIC; n++) {
    if (fs.existsSync(path.join(UPLOAD_DIR, fileFor(topic, n)))) out.push(`/uploads/${fileFor(topic, n)}`);
  }
  return out;
}

async function download(name) {
  const url = `https://commons.wikimedia.org/wiki/Special:FilePath/${encodeURIComponent(name.replace(/ /g, '_'))}?width=${WIDTH}`;
  for (let attempt = 0; attempt < 3; attempt++) {
    const res = await fetch(url, { headers: { 'User-Agent': UA }, redirect: 'follow', signal: AbortSignal.timeout(30000) });
    if (res.status === 429 || res.status >= 500) { await sleep(2500 * (attempt + 1)); continue; }
    if (!res.ok) return null;
    const buf = Buffer.from(await res.arrayBuffer());
    // JPEG magic bytes and a sane size, so an HTML error page is never stored as a photo
    if (buf.length < 8000 || buf[0] !== 0xff || buf[1] !== 0xd8) return null;
    return buf;
  }
  return null;
}

/**
 * Downloads missing photos. Never throws: returns { fetched, cached, failed, offline }.
 * Set SEED_PHOTOS=0 to skip the network entirely, SEED_REFRESH_PHOTOS=1 to re-download.
 */
export async function prefetchPhotos(log = () => {}) {
  const stats = { fetched: 0, cached: 0, failed: 0, offline: false };
  if (process.env.SEED_PHOTOS === '0') { stats.offline = true; return stats; }
  fs.mkdirSync(UPLOAD_DIR, { recursive: true });
  const refresh = process.env.SEED_REFRESH_PHOTOS === '1';
  let consecutiveNetFails = 0;
  for (const [topic, names] of Object.entries(PHOTO_SETS)) {
    let have = 0;
    for (let n = 1; n <= PER_TOPIC; n++) if (!refresh && fs.existsSync(path.join(UPLOAD_DIR, fileFor(topic, n)))) have++;
    if (have >= Math.min(PER_TOPIC, names.length)) { stats.cached += have; continue; }
    let slot = 0;
    for (const name of names) {
      if (slot >= PER_TOPIC) break;
      const target = path.join(UPLOAD_DIR, fileFor(topic, slot + 1));
      if (!refresh && fs.existsSync(target)) { slot++; stats.cached++; continue; }
      try {
        const buf = await download(name);
        consecutiveNetFails = 0;
        if (buf) { fs.writeFileSync(target, buf); slot++; stats.fetched++; log(`photo ${topic} ${slot}/${PER_TOPIC}`); } else stats.failed++;
      } catch {
        stats.failed++;
        if (++consecutiveNetFails >= 3) { stats.offline = true; return stats; }
      }
      await sleep(600);
    }
  }
  return stats;
}
