import { db, resetSchema, tx } from './db.js';
import { hashPassword, now, DAY } from './util.js';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { routeIssue, award } from './logic.js';
import { UPLOAD_DIR } from './media.js';
import { CONFIG } from './config.js';
import { photosFor, prefetchPhotos } from './photos.js';

// Centre of the demo area (Raipur, Chhattisgarh). The iOS simulator is pointed here too.
export const BASE = { lat: 21.2514, lng: 81.6296 };

// Small deterministic PRNG so reseeding gives the same world.
let seedState = 42;
const rnd = () => { seedState = (seedState * 1664525 + 1013904223) % 4294967296; return seedState / 4294967296; };
const pick = (a) => a[Math.floor(rnd() * a.length)];
const jitter = (range) => (rnd() - 0.5) * 2 * range;

// Fictional parties on purpose: the demo must never imply real affiliations.
const PARTIES = ['Chhattisgarh Jan Party', 'Lok Vikas Morcha', 'Hariyali Front', 'Nagrik Manch'];

/**
 * Geography + leaders. Hierarchy of areas: region > state > city > ward.
 * Hierarchy of leaders: state minister > MP > MLA > ward councillor.
 * Ward tuple: [name, party, dLat, dLng, quality (0..1 share of issues that get fixed), issueCount]
 */
const WORLD = [
  {
    region: 'Central India',
    states: [
      {
        name: 'Chhattisgarh',
        minister: ['Savitri Baghel', PARTIES[1], 'Urban Administration'],
        cities: [
          {
            name: 'Raipur', lat: BASE.lat, lng: BASE.lng, radius: 30,
            mps: [['Rohit Tandon', PARTIES[0], 'Raipur East Lok Sabha'], ['Meenakshi Sahu', PARTIES[1], 'Raipur West Lok Sabha']],
            mlas: [
              ['Sanjay Deshlahre', PARTIES[0], 'Raipur City North', 0],
              ['Farida Khan', PARTIES[2], 'Raipur City South', 0],
              ['Vikram Chandel', PARTIES[1], 'Raipur West', 1],
            ],
            wards: [
              ['Lakshmi Sahu', PARTIES[0], 'Telibandha Ward', 0, 0.012, -0.014, 0.75, 7],
              ['Imran Qureshi', PARTIES[3], 'Pandri Ward', 0, -0.014, -0.012, 0.45, 7],
              ['Divya Thakur', PARTIES[2], 'Shankar Nagar Ward', 1, 0.016, 0.014, 0.9, 7],
              ['Arjun Netam', PARTIES[2], 'Mowa Ward', 1, -0.002, 0.018, 0.6, 7],
              ['Nisha Kashyap', PARTIES[1], 'Devendra Nagar Ward', 2, -0.018, 0.012, 0.3, 7],
              ['Tikaram Sonwani', PARTIES[3], 'Gudhiyari Ward', 2, 0.001, -0.026, 0.55, 7],
            ],
          },
          {
            name: 'Bilaspur', lat: 22.0797, lng: 82.1409, radius: 20,
            mps: [['Kavita Pandey', PARTIES[0], 'Bilaspur Lok Sabha']],
            mlas: [['Prakash Dubey', PARTIES[3], 'Bilaspur City', 0]],
            wards: [
              ['Sunita Rathore', PARTIES[0], 'Sarkanda Ward', 0, 0.006, -0.004, 0.8, 6],
              ['Gopal Mishra', PARTIES[3], 'Tifra Ward', 0, -0.007, 0.006, 0.5, 6],
            ],
          },
          {
            name: 'Bhilai-Durg', lat: 21.1938, lng: 81.3509, radius: 20,
            mps: [['Ashok Sinha', PARTIES[1], 'Durg Lok Sabha']],
            mlas: [['Rekha Dewangan', PARTIES[1], 'Bhilai Nagar', 0]],
            wards: [
              ['Karthik Yadav', PARTIES[3], 'Supela Ward', 0, 0.008, -0.006, 0.35, 6],
              ['Anita Chandrakar', PARTIES[1], 'Civic Centre Ward', 0, -0.01, 0.008, 0.25, 3],
            ],
          },
          {
            name: 'Korba', lat: 22.3595, lng: 82.7501, radius: 20,
            mps: [['Lalit Kanwar', PARTIES[2], 'Korba Lok Sabha']],
            mlas: [['Padma Rajwade', PARTIES[2], 'Korba City', 0]],
            wards: [
              ['Bhupendra Patel', PARTIES[2], 'Kosabadi Ward', 0, 0.007, -0.005, 0.65, 6],
              ['Shanti Markam', PARTIES[0], 'Transport Nagar Ward', 0, -0.008, 0.006, 0.5, 6],
            ],
          },
        ],
      },
      {
        name: 'Madhya Pradesh',
        minister: ['Rajendra Bhargava', PARTIES[0], 'Housing & Urban Affairs'],
        cities: [
          {
            name: 'Bhopal', lat: 23.2599, lng: 77.4126, radius: 30,
            mps: [['Alka Joshi', PARTIES[0], 'Bhopal Lok Sabha']],
            mlas: [['Neha Pawar', PARTIES[0], 'Bhopal South', 0]],
            wards: [
              ['Rajesh Malviya', PARTIES[0], 'New Market Ward', 0, -0.008, 0.004, 0.95, 8],
              ['Farhat Ali', PARTIES[3], 'Arera Colony Ward', 0, 0.007, -0.005, 0.9, 8],
            ],
          },
        ],
      },
    ],
  },
  {
    region: 'East India',
    states: [
      {
        name: 'Odisha',
        minister: ['Smita Mohanty', PARTIES[2], 'Housing & Urban Development'],
        cities: [
          {
            name: 'Bhubaneswar', lat: 20.2961, lng: 85.8245, radius: 25,
            mps: [['Bijay Nayak', PARTIES[2], 'Bhubaneswar Lok Sabha']],
            mlas: [['Jyoti Sahoo', PARTIES[2], 'Bhubaneswar Central', 0]],
            wards: [
              ['Pratap Das', PARTIES[2], 'Saheed Nagar Ward', 0, 0.006, -0.004, 0.7, 6],
              ['Lipika Behera', PARTIES[1], 'Unit 4 Ward', 0, -0.007, 0.006, 0.55, 6],
            ],
          },
        ],
      },
    ],
  },
];

const PEOPLE = ['Hemant Sahu', 'Kiran Mahant', 'Dilip Thakur', 'Poonam Yadav', 'Ramesh Chandrakar', 'Sunita Netam',
  'Anil Dewangan', 'Meena Sinha', 'Gaurav Tiwari', 'Rekha Patel', 'Deepak Kashyap', 'Anita Sahu'];

// Local places per city, used to word the bulk issues so they read like real complaints.
const PLACES = {
  Raipur: ['Pandri', 'Shankar Nagar', 'Mowa', 'Devendra Nagar', 'Fafadih', 'Gudhiyari', 'Tatibandh', 'Kota', 'Amapara', 'Sunder Nagar', 'Civil Lines', 'Samta Colony'],
  'Bhilai-Durg': ['Supela', 'Nehru Nagar', 'Smriti Nagar', 'Sector 6', 'Risali', 'Kohka', 'Power House'],
  Korba: ['Transport Nagar', 'Kosabadi', 'Rampur', 'Indira Stadium Road', 'Balco Nagar', 'Sarvamangala'],
  Bhopal: ['New Market', 'Arera Colony', 'MP Nagar', 'Habibganj', 'Kolar Road', 'Shahpura'],
  Bhubaneswar: ['Saheed Nagar', 'Unit 4', 'Kharvel Nagar', 'Jaydev Vihar', 'Patia', 'Nayapalli'],
};

// [title, description] per category. {p} is replaced with a local place name.
const TEMPLATES = {
  road: [
    ['Deep pothole near the {p} bus stop', 'The pothole is about a foot deep and fills with water when it rains. Two-wheelers swerve into the oncoming lane to avoid it.'],
    ['Broken footpath tiles outside {p} market', 'Several slabs have cracked and sunk. Older people are walking on the road instead of the footpath.'],
    ['Road has caved in near the {p} culvert', 'A stretch of about three metres sank after the last heavy rain. The barricade put up earlier has since disappeared.'],
    ['No speed breaker outside the government school at {p}', 'Vehicles cross at speed during school hours. Parents have asked for a marked crossing and a speed breaker.'],
  ],
  garbage: [
    ['Garbage not lifted in {p} for over a week', 'The collection vehicle has not come since last Tuesday. The bins are overflowing and the lane smells badly by afternoon.'],
    ['Overflowing bins at the {p} sabzi mandi', 'Vegetable waste is left on the road after the evening market and stray cattle spread it further.'],
    ['Waste dumped on the vacant plot near {p}', 'Households and small shops dump waste here at night. The heap is now about the size of a car.'],
  ],
  water: [
    ['No water supply in {p} since Monday', 'The morning supply has not come for several days. Families are paying for private tankers.'],
    ['Main pipe leaking near {p} chowk', 'Treated water has been running onto the road for days and pressure in the neighbouring lanes has dropped.'],
    ['Tap water in {p} is muddy and smells', 'The water has been brown since the pipeline work last week. Several families report stomach illness.'],
  ],
  drainage: [
    ['Open nala overflowing onto the road near {p}', 'The nala is choked with plastic and silt and spills onto the road after even a short shower.'],
    ['Storm drain blocked at the {p} crossing', 'Rainwater stands knee-deep at the crossing for hours. Shops on both sides have had water inside.'],
    ['Manhole cover missing on the {p} main road', 'The cover went missing over the weekend. It is hard to see at night and dangerous for two-wheelers.'],
  ],
  electricity: [
    ['Power cuts every evening in {p}', 'Supply goes off most evenings between 7 and 10 pm, with no notice from the department.'],
    ['Transformer at {p} is sparking', 'It sparks whenever the load rises and the wires hang low enough for children playing nearby to reach.'],
  ],
  streetlight: [
    ['Streetlights not working along the {p} lane', 'Around eight poles have been dark for two weeks. Women and older residents avoid the lane after dark.'],
    ['Flickering lamp at {p} chowk', 'The lamp flickers and goes out for long stretches. It is the only light at this junction.'],
  ],
  safety: [
    ['Underpass near {p} has no lighting', 'The underpass is completely dark after sunset and people prefer to cross the road above it.'],
    ['Stray cattle blocking the {p} main road', 'Cows sit in the middle of the road every evening and have caused several near misses.'],
  ],
  park: [
    ["Broken swings in the {p} children's park", 'Two swings have snapped chains and the slide has a sharp edge. Parents are keeping children away.'],
    ['Damaged railing at the {p} talab', 'Part of the railing beside the water has collapsed, and children play right at the edge.'],
  ],
  other: [
    ['Illegal hoardings blocking the view at {p} junction', 'Large hoardings put up without permission block drivers\' view of the turn.'],
  ],
};

const RESOLVED_NOTE = {
  road: 'Pothole filled and the surface levelled by the Public Works team',
  garbage: 'Waste cleared and a daily pickup slot fixed for the lane',
  water: 'Pipeline repaired and supply restored after a pressure test',
  drainage: 'Drain desilted and the cover replaced by the ward office',
  electricity: 'Transformer inspected and the loose cables replaced',
  streetlight: 'Faulty lamps replaced and the circuit rewired',
  safety: 'Lighting installed and the area patrolled',
  park: 'Equipment repaired and repainted by the parks department',
  other: 'Hoardings removed by the enforcement squad',
};

// issue category -> photo topic
const PHOTO_TOPIC = {
  road: 'pothole', garbage: 'garbage', water: 'water', drainage: 'drainage', electricity: 'electricity',
  streetlight: 'streetlight', safety: 'streetlight', park: 'park', other: 'market',
};
const topicForIssue = (category, title) => (category === 'safety' && /stray|cattle|dog/i.test(title) ? 'animal' : PHOTO_TOPIC[category] || 'market');

export function seed() {
  resetSchema();
  seedState = 42;

  tx(() => {
    // ---------- areas + politicians ----------
    const insArea = db.prepare('INSERT INTO areas (name,kind,parent_id,lat,lng,radius_km) VALUES (?,?,?,?,?,?)');
    const insPol = db.prepare(`INSERT INTO politicians (name,party,constituency,level,parent_id,area_id,city_id,state_id,region_id,hue,tagline)
      VALUES (?,?,?,?,?,?,?,?,?,?,?)`);
    let hueSeed = 0;
    const pol = (name, party, constituency, level, parentId, areaId, cityId, stateId, regionId, tagline) => {
      hueSeed += 1;
      return Number(insPol.run(name, party, constituency, level, parentId, areaId, cityId, stateId, regionId, (hueSeed * 47) % 360, tagline).lastInsertRowid);
    };

    const wardQuality = new Map(); // ward area id -> { quality, count }
    for (const reg of WORLD) {
      const regionId = Number(insArea.run(reg.region, 'region', null, null, null, null).lastInsertRowid);
      for (const st of reg.states) {
        const stateId = Number(insArea.run(st.name, 'state', regionId, null, null, null).lastInsertRowid);
        const minister = pol(st.minister[0], st.minister[1], st.minister[2], 'minister', null, stateId, null, stateId, regionId, `Minister · ${st.minister[2]}`);
        for (const c of st.cities) {
          const cityId = Number(insArea.run(c.name, 'city', stateId, c.lat, c.lng, c.radius).lastInsertRowid);
          const mpIds = c.mps.map((m) => pol(m[0], m[1], m[2], 'mp', minister, cityId, cityId, stateId, regionId, 'Member of Parliament'));
          const mlaIds = c.mlas.map((m) => pol(m[0], m[1], m[2], 'mla', mpIds[m[3]], cityId, cityId, stateId, regionId, 'Member of Legislative Assembly'));
          for (const w of c.wards) {
            const wardId = Number(insArea.run(w[2], 'ward', cityId, c.lat + w[4], c.lng + w[5], 3.5).lastInsertRowid);
            pol(w[0], w[1], w[2], 'ward', mlaIds[w[3]], wardId, cityId, stateId, regionId, 'Ward Councillor');
            wardQuality.set(wardId, { quality: w[6], count: w[7] });
          }
        }
      }
    }

    // ---------- users ----------
    const mkUser = (name, email, password, opts = {}) => {
      const { hash, salt } = hashPassword(password);
      const info = db.prepare(`INSERT INTO users (name,email,password_hash,salt,points,volunteer,alert_radius_km,home_lat,home_lng,hue,created_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?)`)
        .run(name, email, hash, salt, 0, opts.volunteer ? 1 : 0, opts.radius ?? 5,
          BASE.lat + jitter(0.012), BASE.lng + jitter(0.012), Math.floor(rnd() * 360), now() - 60 * DAY);
      return Number(info.lastInsertRowid);
    };
    const demo = mkUser('Alex Rathore', 'demo@bythepeople.app', 'demo1234', { volunteer: true, radius: 6 });
    const people = PEOPLE.map((n, i) => mkUser(n, `${n.split(' ')[0].toLowerCase()}@bythepeople.app`, 'sober123', { volunteer: i % 2 === 0 }));
    const demo2 = mkUser('Guest Citizen', 'guest@bythepeople.app', 'guest123');

    const history = (issueId, status, note, userId, at, extra = {}) =>
      db.prepare('INSERT INTO status_history (issue_id,status,note,user_id,created_at,media,actor_role,kind) VALUES (?,?,?,?,?,?,?,?)')
        .run(issueId, status, note, userId, at, JSON.stringify(extra.media || []),
          userId ? db.prepare('SELECT role FROM users WHERE id=?').get(userId).role : null, extra.kind || (userId ? 'status' : 'system'));

    const insertIssue = (o) => {
      const route = routeIssue(o.lat, o.lng);
      if (!route) throw new Error(`Seed issue outside coverage: ${o.title}`);
      const created = now() - o.ageDays * DAY;
      const info = db.prepare(`INSERT INTO issues (title,description,category,lat,lng,address,reporter_id,politician_id,ward_id,city_id,state_id,region_id,status,round,created_at,event_at,scheduled_at,resolved_at,closed_at,resolution_note)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`)
        .run(o.title, o.description || '', o.category, o.lat, o.lng, o.address || null, o.reporter, route.politician.id,
          route.chain.ward.id, route.chain.city.id, route.chain.state.id, route.chain.region.id, o.status, 1,
          created, o.eventAt ?? null, o.scheduledAt ?? null, o.resolvedAt ?? null, o.closedAt ?? null, o.note ?? null);
      const id = Number(info.lastInsertRowid);
      history(id, 'open', 'Issue reported', o.reporter, created);
      const sups = [o.reporter, ...(o.supporters || [])];
      sups.forEach((u, k) => db.prepare('INSERT OR IGNORE INTO supports (issue_id,user_id,created_at) VALUES (?,?,?)').run(id, u, created + k * 3600000));
      if (o.eventAt) history(id, 'event', 'Reached 5 supporters and became an event', null, o.eventAt);
      (o.volunteers || []).forEach((u, k) => {
        db.prepare('INSERT INTO volunteers (issue_id,user_id,role,joined_at) VALUES (?,?,?,?)').run(id, u, k === 0 ? 'organiser' : 'volunteer', (o.eventAt || created) + (k + 1) * 3600000);
      });
      if ((o.volunteers || []).length) history(id, 'in_progress', 'First volunteer became the organiser', o.volunteers[0], (o.eventAt || created) + 3600000);
      if (o.resolvedAt) history(id, 'pending_verification', `Marked resolved: ${o.note}`, o.volunteers[0], o.resolvedAt);
      if (o.closedAt) history(id, 'closed', 'Resolution verified by neighbours', null, o.closedAt);
      return id;
    };

    // ---------- bulk history per ward (drives Neta scores & rarity) ----------
    const cats = Object.keys(TEMPLATES);
    const wards = db.prepare("SELECT w.*, c.name AS city_name FROM areas w JOIN areas c ON c.id=w.parent_id WHERE w.kind='ward' ORDER BY w.id").all();
    const evenPeople = people.filter((_, k) => k % 2 === 0);
    for (const w of wards) {
      const { quality, count } = wardQuality.get(w.id);
      const places = PLACES[w.city_name] || [w.name.replace(/ Ward$/, '')];
      for (let i = 0; i < count; i++) {
        const cat = pick(cats);
        const [titleT, desc] = pick(TEMPLATES[cat]);
        const title = titleT.replace('{p}', pick(places));
        const lat = w.lat + jitter(0.014);
        const lng = w.lng + jitter(0.014);
        const reporter = pick(people);
        const others = people.filter((p) => p !== reporter);
        if (rnd() < quality) {
          const age = 20 + Math.floor(rnd() * 70);
          const eventAt = now() - (age - 3) * DAY;
          const days = 4 + Math.floor(rnd() * 20);
          insertIssue({ lat, lng, category: cat, title, reporter, supporters: others.slice(0, 5 + Math.floor(rnd() * 3)),
            volunteers: [pick(evenPeople)], status: 'closed', ageDays: age, eventAt, resolvedAt: eventAt + days * DAY, closedAt: eventAt + (days + 1) * DAY,
            note: RESOLVED_NOTE[cat], description: desc });
        } else if (rnd() < 0.3) {
          const age = 3 + Math.floor(rnd() * 8);
          insertIssue({ lat, lng, category: cat, title, reporter, supporters: others.slice(0, 5), status: 'event',
            ageDays: age, eventAt: now() - 1 * DAY, scheduledAt: now() + (1 + Math.floor(rnd() * 5)) * DAY,
            description: `${desc} Neighbours have backed this report and volunteers are being organised.` });
        } else {
          insertIssue({ lat, lng, category: cat, title, reporter, supporters: others.slice(0, Math.floor(rnd() * 4)),
            status: 'open', ageDays: 1 + Math.floor(rnd() * 25), description: desc });
        }
      }
    }

    // ---------- hand-made Raipur journey around the demo location ----------
    const evA = insertIssue({ lat: BASE.lat + 0.006, lng: BASE.lng + 0.004, category: 'garbage', title: 'Garbage dump behind Telibandha lake',
      description: 'Waste from the lakeside stalls has been piling up behind the boundary wall for about three weeks. Residents are planning a safai abhiyan and need hands for the weekend.', reporter: people[1],
      supporters: [people[2], people[3], people[4], people[5]], status: 'event', ageDays: 4, eventAt: now() - 1 * DAY, scheduledAt: now() + 2 * DAY });
    const evB = insertIssue({ lat: BASE.lat - 0.004, lng: BASE.lng - 0.006, category: 'road', title: 'Pothole cluster on Pandri Road',
      description: 'There are six potholes in a 200 metre stretch near the Pandri flyover. Two motorcyclists have already skidded here this month.', reporter: people[6],
      supporters: [people[0], people[2], people[7], people[8]], volunteers: [people[0], demo],
      status: 'in_progress', ageDays: 6, eventAt: now() - 2 * DAY, scheduledAt: now() + 1 * DAY });
    insertIssue({ lat: BASE.lat + 0.01, lng: BASE.lng - 0.003, category: 'park', title: "Broken swings at the lakeside children's park",
      description: 'Two swings have snapped chains and the slide has a cracked edge. Children from the nearby colonies have nowhere safe to play.', reporter: people[3],
      supporters: [people[4], people[5], people[9], people[10]], volunteers: [people[4]], status: 'in_progress', ageDays: 9,
      eventAt: now() - 4 * DAY, scheduledAt: now() + 4 * DAY });
    const evD = insertIssue({ lat: BASE.lat + 0.002, lng: BASE.lng + 0.009, category: 'drainage', title: 'Blocked drain flooding Mowa Road',
      description: 'The drain along Mowa Road is choked with silt and water stands knee-deep after every shower. Two shops have had water inside.', reporter: people[5],
      supporters: [demo, people[1], people[7], people[9]], volunteers: [people[8], people[10]],
      status: 'pending_verification', ageDays: 12, eventAt: now() - 8 * DAY, scheduledAt: now() - 2 * DAY,
      resolvedAt: now() - 1 * DAY, note: 'Drain desilted and the cover replaced' });
    // 4 supporters: one more support triggers the event conversion
    insertIssue({ lat: BASE.lat + 0.0015, lng: BASE.lng + 0.001, category: 'streetlight', title: 'Street lights out on Shankar Nagar Road',
      description: 'The whole stretch has been dark for ten days. Morning and evening walkers have stopped using this road.', reporter: people[0],
      supporters: [people[2], people[4], people[6]], status: 'open', ageDays: 5 });
    insertIssue({ lat: BASE.lat - 0.002, lng: BASE.lng + 0.002, category: 'garbage', title: 'Overflowing bins at Pandri market',
      description: 'The bins have not been emptied since the weekend. The smell reaches the neighbouring shops and stray dogs are tearing the bags open.', reporter: people[7],
      supporters: [people[1], people[3]], status: 'open', ageDays: 3 });
    insertIssue({ lat: BASE.lat + 0.003, lng: BASE.lng - 0.002, category: 'water', title: 'No water supply for 3 days in Devendra Nagar',
      description: 'The morning supply has not arrived since Sunday. Residents of about forty homes are buying tankers at 400 rupees a trip.', reporter: people[9],
      supporters: [people[0], people[2], people[5]], status: 'open', ageDays: 3 });
    insertIssue({ lat: BASE.lat - 0.0035, lng: BASE.lng - 0.001, category: 'road', title: 'Missing speed breaker outside the school',
      description: 'Cars pass at speed while children cross at school hours. The parents\' association has asked for a speed breaker and a zebra crossing.', reporter: people[11],
      supporters: [people[8]], status: 'open', ageDays: 2 });
    // inside Raipur but far from the demo user: shows the distance gate
    insertIssue({ lat: BASE.lat + 0.03, lng: BASE.lng + 0.03, category: 'electricity', title: 'Sparking transformer near Tatibandh',
      description: 'The transformer sparks every evening and the cables hang low over the lane. It needs an inspection before the rains.', reporter: people[4],
      supporters: [people[2]], status: 'open', ageDays: 8 });

    // ---------- points, badges, notifications ----------
    people.forEach((p, i) => award(p, 40 + i * 35, []));
    award(demo, 62, []);
    award(demo2, 5, []);
    const n = (type, title, body, issueId, ageH) =>
      db.prepare('INSERT INTO notifications (user_id,type,title,body,issue_id,read,created_at,ref_type,ref_id) VALUES (?,?,?,?,?,?,?,?,?)')
        .run(demo, type, title, body, issueId, 0, now() - ageH * 3600000, 'issue', issueId);
    n('event_nearby', 'New event near you', '"Garbage dump behind Telibandha lake" needs volunteers', evA, 20);
    n('verify_request', 'Is it really fixed?', 'Please verify "Blocked drain flooding Mowa Road" if you are nearby', evD, 5);
    n('event_scheduled', 'Event rescheduled', '"Pothole cluster on Pandri Road" is happening tomorrow', evB, 3);

    seedSocial({ people, demo, demo2, insertIssue, history });
  });
}

// ---------- v3 seed: roles, gatherings, clubs, donations, comments, likes ----------
const HOUR = 3600000;
const MIN = 60000;

function crc32(buf) {
  let c; let crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}

/** Tiny gradient PNG so seeded media renders as coloured cards without shipping binaries. */
function gradientPng(w, h, hue) {
  const hsl = (hh, l) => {
    const a = 0.55 * Math.min(l, 1 - l);
    const f = (nn) => { const k = (nn + hh / 30) % 12; return Math.round(255 * (l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1)))); };
    return [f(0), f(8), f(4)];
  };
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 3 + 1)] = 0;
    for (let x = 0; x < w; x++) {
      const [r, g, b] = hsl((hue + (x / w) * 40) % 360, 0.35 + 0.35 * (1 - y / h));
      const o = y * (w * 3 + 1) + 1 + x * 3;
      raw[o] = r; raw[o + 1] = g; raw[o + 2] = b;
    }
  }
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

function makeSeedMedia() {
  fs.mkdirSync(UPLOAD_DIR, { recursive: true });
  const urls = [];
  for (let i = 0; i < 12; i++) {
    const name = `seed-${i + 1}.png`;
    fs.writeFileSync(path.join(UPLOAD_DIR, name), gradientPng(96, 64, (i * 30 + 10) % 360));
    urls.push(`/uploads/${name}`);
  }
  return urls;
}

function seedSocial({ people, demo, demo2, insertIssue, history }) {
  const t0 = now();
  const M = makeSeedMedia();
  const topicHue = (t) => [...t].reduce((a, c) => a + c.charCodeAt(0), 0);
  // Real photos for a topic (downloaded by prefetchPhotos), else a generated placeholder.
  const ph = (topic, ...idx) => {
    const list = photosFor(topic);
    const pool = list.length ? list : [M[topicHue(topic) % M.length]];
    return [...new Set(idx.map((k) => pool[k % pool.length]))];
  };
  const raipur = db.prepare("SELECT id FROM areas WHERE kind='city' AND name='Raipur'").get().id;
  const lakshmi = db.prepare("SELECT * FROM politicians WHERE name='Lakshmi Sahu'").get();

  // ----- role accounts -----
  const mkAcct = (o) => {
    const { hash, salt } = hashPassword(o.password);
    return Number(db.prepare(`INSERT INTO users (name,email,password_hash,salt,points,volunteer,alert_radius_km,home_lat,home_lng,hue,created_at,
        role,org_name,reg_no,verified,verify_status,about,needs,address,department_name,politician_id,designation,city_id)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`)
      .run(o.name, o.email, hash, salt, o.points || 0, 0, 15, o.lat, o.lng, o.hue, t0 - 90 * DAY,
        o.role, o.orgName || null, o.regNo || null, o.verified === false ? 0 : 1, o.verified === false ? 'pending' : 'verified',
        o.about || null, JSON.stringify(o.needs || []), o.address || null, o.department || null, o.politicianId || null,
        o.designation || null, o.cityId || null).lastInsertRowid);
  };
  const admin = mkAcct({ name: 'Priya Dubey', email: 'admin@bythepeople.app', password: 'admin1234', role: 'admin', hue: 210,
    lat: BASE.lat + 0.004, lng: BASE.lng + 0.002, department: 'Raipur Municipal Corporation', designation: 'Zonal Commissioner', cityId: raipur });
  const neta = mkAcct({ name: 'Lakshmi Sahu', email: 'neta@bythepeople.app', password: 'neta1234', role: 'neta', hue: 24,
    lat: BASE.lat + 0.012, lng: BASE.lng - 0.014, politicianId: lakshmi.id, designation: 'Ward Councillor, Telibandha', cityId: raipur });
  const seva = mkAcct({ name: 'Meera Joshi', email: 'seva@bythepeople.app', password: 'seva1234', role: 'foundation', hue: 150,
    orgName: 'Seva Sankalp Foundation', regNo: 'CG/NGO/2014/0412', needs: ['food', 'clothes', 'books'],
    about: 'We run two community kitchens and a winter clothing bank for families in Raipur, and have done so since 2014.', address: 'Shankar Nagar, Raipur',
    lat: BASE.lat + 0.014, lng: BASE.lng + 0.012 });
  const anna = mkAcct({ name: 'Harish Agrawal', email: 'annapurna@bythepeople.app', password: 'anna1234', role: 'foundation', hue: 35,
    orgName: 'Annapurna Food Bank', regNo: 'CG/NGO/2011/0098', needs: ['food', 'essentials'],
    about: 'We collect surplus cooked food from caterers and canteens and serve more than 300 people every evening at four points in Raipur.', address: 'Pandri Market Road, Raipur',
    lat: BASE.lat - 0.012, lng: BASE.lng - 0.01 });
  const hope = mkAcct({ name: 'Rohan Meshram', email: 'newhope@bythepeople.app', password: 'hope1234', role: 'foundation', hue: 280,
    orgName: 'New Hope Trust', regNo: 'CG/NGO/2023/1187', verified: false, needs: ['clothes', 'toys'],
    about: 'A new trust working with school-age children in the bastis around Mowa. Registration documents have been submitted for verification.', address: 'Mowa, Raipur',
    lat: BASE.lat + 0.002, lng: BASE.lng + 0.017 });

  const bal = mkAcct({ name: 'Sister Anita Dsouza', email: 'balvikas@bythepeople.app', password: 'bal1234', role: 'foundation', hue: 12,
    orgName: 'Bal Vikas Anathalaya', regNo: 'CG/NGO/2008/0231', needs: ['food', 'clothes', 'stationery', 'medicine'],
    about: 'An orphanage home to 54 children aged 4 to 17 in Sector 6, Bhilai. We run on small donations and need warm clothes, school supplies and regular meals.', address: 'Sector 6, Bhilai',
    lat: BASE.lat - 0.058, lng: BASE.lng - 0.249 });
  const vri = mkAcct({ name: 'Mohan Lal Verma', email: 'vridhashram@bythepeople.app', password: 'vri1234', role: 'foundation', hue: 195,
    orgName: 'Shanti Vridhashram', regNo: 'CG/NGO/2005/0117', needs: ['food', 'clothes', 'medicine', 'volunteers'],
    about: 'An old-age home for 38 residents in Durg, many with no family left. Evening company, medicines and warm blankets matter most to them.', address: 'Padmanabhpur, Durg',
    lat: BASE.lat - 0.04, lng: BASE.lng - 0.31 });
  const ras = mkAcct({ name: 'Farhat Siddiqui', email: 'rainbasera@bythepeople.app', password: 'ras1234', role: 'foundation', hue: 330,
    orgName: 'Raen Basera Night Shelter', regNo: 'CG/NGO/2016/0654', needs: ['food', 'clothes', 'essentials'],
    about: 'A 60-bed night shelter near Raipur railway station for the homeless and for families of patients at the nearby hospital. Open every night of the year.', address: 'Station Road, Raipur',
    lat: BASE.lat - 0.017, lng: BASE.lng + 0.004 });
  const drs = mkAcct({ name: 'Dr. Alka Pandey', email: 'drishti@bythepeople.app', password: 'drishti1234', role: 'foundation', hue: 255,
    orgName: 'Drishti Blind Care Centre', regNo: 'CG/NGO/2012/0376', needs: ['stationery', 'medicine', 'volunteers', 'money'],
    about: 'A residential centre for 40 visually impaired students in Raipur. We teach Braille and computer skills and always need scribes, audio books and volunteers.', address: 'Kota, Raipur',
    lat: BASE.lat - 0.009, lng: BASE.lng - 0.022 });

  const setOrg = (id, topic) => {
    const [cover, avatar] = ph(topic, 0, 1);
    db.prepare('UPDATE users SET avatar_url=?, cover_url=? WHERE id=?').run(avatar || cover, cover, id);
  };
  setOrg(seva, 'food'); setOrg(anna, 'thali'); setOrg(hope, 'ngo');
  setOrg(bal, 'toys'); setOrg(vri, 'shelter'); setOrg(ras, 'shelter'); setOrg(drs, 'books');

  // ----- issue extras: Telibandha ward (the demo neta's patch) with authority + escalation story -----
  const TC = { lat: BASE.lat + 0.011, lng: BASE.lng - 0.013 };
  const pt = (a, b) => ({ lat: TC.lat + a, lng: TC.lng + b });
  const setIssue = (id, cols) => {
    const keys = Object.keys(cols);
    db.prepare(`UPDATE issues SET ${keys.map((k) => `${k}=?`).join(',')} WHERE id=?`).run(...keys.map((k) => cols[k]), id);
  };
  const auth = (id, status, note, ageH, extra = {}) => history(id, status, note, admin, t0 - ageH * HOUR, { kind: 'authority', ...extra });
  const mkIssue = (o) => insertIssue({ ...o, status: 'open' });

  const i1 = mkIssue({ ...pt(0.002, 0.001), category: 'streetlight', title: 'Dead streetlights along Telibandha ring road',
    description: 'Eleven poles have been dark for two weeks. Two chain snatching cases were reported on this stretch after dark.', reporter: people[2], supporters: [people[4], people[6], demo2], ageDays: 6 });
  setIssue(i1, { authority_status: 'acknowledged', media: JSON.stringify(ph('streetlight', 0)) });
  auth(i1, 'open', 'Acknowledged by Street Lighting. A survey team will visit tomorrow.', 70);

  const i2 = mkIssue({ ...pt(-0.003, 0.002), category: 'drainage', title: 'Open manhole beside Telibandha chowk',
    description: 'The cover has been missing for a week. A cyclist has already fallen in and children walk past it on the way to school.', reporter: people[5], supporters: [people[1], people[3], people[8], people[9]], ageDays: 9 });
  setIssue(i2, { escalated: 1, escalated_by: neta, escalation_note: 'Safety hazard near a school, unresolved for nine days. Needs urgent action.', media: JSON.stringify(ph('drainage', 0, 1)) });
  history(i2, 'open', 'Escalated to admin portal by Lakshmi Sahu: Safety hazard near a school, unresolved for 9 days.', neta, t0 - 30 * HOUR, { kind: 'neta' });

  const i3 = mkIssue({ ...pt(0.004, -0.002), category: 'garbage', title: 'Garbage truck skipping Lakeview lane',
    description: 'The garbage vehicle has skipped this lane for ten days and the bins now overflow onto the road.', reporter: people[7], supporters: [people[0], people[6]], ageDays: 12 });
  setIssue(i3, { status: 'in_progress', authority_status: 'in_progress', assigned_to: 'Sanitation Team B (Ramesh Verma)' });
  auth(i3, 'open', 'Acknowledged by Solid Waste Management.', 160);
  auth(i3, 'in_progress', 'Work has started (Solid Waste Management) (assigned to Sanitation Team B (Ramesh Verma))', 100);
  history(i3, 'in_progress', 'Lakshmi Sahu: I have asked the zone office for a daily pickup schedule on this lane.', neta, t0 - 90 * HOUR, { kind: 'neta' });

  const i4 = mkIssue({ ...pt(-0.001, -0.004), category: 'water', title: 'Burst water pipeline on Marine Drive',
    description: 'Clean water has been running from a burst joint onto the road since Monday. Pressure in the surrounding lanes is very low.', reporter: people[9], supporters: [demo, people[1], people[3], people[10]], ageDays: 8 });
  setIssue(i4, { status: 'pending_verification', authority_status: 'resolved', resolved_at: t0 - 6 * HOUR,
    resolution_note: 'Pipeline joint replaced and pressure tested', media: JSON.stringify(ph('water', 0)) });
  auth(i4, 'open', 'Acknowledged by Water Supply.', 150);
  auth(i4, 'in_progress', 'Work has started (Water Supply)', 120);
  auth(i4, 'pending_verification', 'Marked resolved by Raipur Municipal Corporation: Pipeline joint replaced and pressure tested', 6, { media: ph('water', 1, 2) });

  const i5 = mkIssue({ ...pt(0.005, 0.003), category: 'park', title: 'Broken benches on the lake promenade',
    description: 'Around half of the benches along the promenade are cracked or missing, and there is nowhere for older walkers to sit.', reporter: people[3], supporters: [people[4], people[5], people[8], people[11]], ageDays: 25 });
  setIssue(i5, { status: 'closed', authority_status: 'resolved', closed_at: t0 - 8 * DAY, resolved_at: t0 - 9 * DAY, resolution_note: 'All damaged benches replaced', media: JSON.stringify(ph('park', 1)) });
  auth(i5, 'open', 'Acknowledged by Parks & Gardens.', 24 * 20);
  auth(i5, 'pending_verification', 'Marked resolved by Raipur Municipal Corporation: All benches replaced', 24 * 9, { media: ph('park', 2) });
  history(i5, 'closed', 'Resolution verified by neighbours', null, t0 - 8 * DAY);

  const i6 = mkIssue({ ...pt(-0.004, 0.004), category: 'road', title: 'Potholes outside Telibandha vegetable market',
    description: 'Vendors and customers dodge craters every morning and ambulances have trouble getting through at peak hours.', reporter: people[0], supporters: [people[1], people[2], people[3], demo2], ageDays: 14 });
  setIssue(i6, { escalated: 1, escalated_by: neta, escalation_note: 'Raised in the ward committee twice already. Please prioritise.', media: JSON.stringify(ph('pothole', 0, 1)) });
  history(i6, 'open', 'Escalated to admin portal by Lakshmi Sahu: Raised in the ward committee twice already.', neta, t0 - 50 * HOUR, { kind: 'neta' });
  const i7 = mkIssue({ ...pt(0.0, 0.006), category: 'safety', title: 'Stray dogs menace near the primary school',
    description: 'A pack of about six dogs chases children on their way to school. Residents are asking for a sterilisation and vaccination drive.', reporter: people[6], supporters: [people[10]], ageDays: 4 });
  setIssue(i7, { media: JSON.stringify(ph('animal', 0)) });

  // every other issue gets one or two photos that match its category
  db.prepare("SELECT id, category, title FROM issues WHERE media='[]' ORDER BY id").all().forEach((r) => {
    const topic = topicForIssue(r.category, r.title);
    setIssue(r.id, { media: JSON.stringify(ph(topic, r.id, ...(r.id % 3 === 0 ? [r.id + 1] : []))) });
  });

  // ----- clubs -----
  const clubIds = {};
  const mkClub = (name, description, category, hue, owner, members, topic) => {
    const [cover, avatar] = ph(topic, 0, 1);
    const id = Number(db.prepare('INSERT INTO clubs (name,description,category,hue,owner_id,avatar_url,cover_url,created_at) VALUES (?,?,?,?,?,?,?,?)')
      .run(name, description, category, hue, owner, avatar || cover, cover, t0 - 60 * DAY).lastInsertRowid);
    [...new Set([owner, ...members])].forEach((u, k) => db.prepare('INSERT INTO club_members (club_id,user_id,joined_at) VALUES (?,?,?)').run(id, u, t0 - (50 - k) * DAY));
    clubIds[name] = id;
    return id;
  };
  const clubRun = mkClub('Raipur Run Club', 'Weekly 5K and 10K runs around Telibandha and Budha talab, every Sunday at 6 am. All paces are welcome.', 'marathon', 200, people[0], [people[1], people[4], people[8], demo, demo2], 'marathon');
  const clubGreen = mkClub('Green Raipur Plantation Club', 'Plants native trees such as neem, arjun and peepal across Raipur and looks after them through the first three summers.', 'plantation', 130, people[1], [people[2], people[3], people[5], people[9], demo], 'plantation');
  const clubStray = mkClub('Stray Care Squad', 'Feeds, vaccinates and finds homes for stray animals, working with two local veterinarians.', 'animal_care', 25, people[3], [people[6], people[7], people[10], demo2], 'animal');
  const clubBlood = mkClub('Blood Warriors', 'Regular donors and volunteers who organise blood camps with the district blood bank.', 'blood', 355, seva, [people[0], people[2], people[5], people[11], demo], 'blood');
  const clubLake = mkClub('Clean Lake Crew', 'Saturday morning clean-ups at Telibandha and Budha talab.', 'cleanup', 175, demo, [people[1], people[4], people[5], people[7], people[9], people[11], demo2], 'cleanup');

  // ----- gatherings -----
  const gids = {};
  const mkG = (key, o) => {
    const id = Number(db.prepare(`INSERT INTO gatherings (title,description,type,lat,lng,address,start_at,end_at,status,organizer_id,club_id,capacity,media,impact_note,completed_at,created_at)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`)
      .run(o.title, o.description, o.type, BASE.lat + o.d[0], BASE.lng + o.d[1], o.address, o.start, o.end ?? null, o.status || 'upcoming',
        o.org, o.club ?? null, o.cap ?? null, JSON.stringify(o.media || []), o.impact ?? null, o.status === 'completed' ? o.start + 4 * HOUR : null, o.start - 10 * DAY).lastInsertRowid);
    gids[key] = id;
    (o.going || []).forEach((u, k) => {
      const checked = o.checked && o.checked.includes(u);
      db.prepare('INSERT OR IGNORE INTO gathering_rsvps (gathering_id,user_id,created_at,checked_in_at) VALUES (?,?,?,?)')
        .run(id, u, o.start - (9 - (k % 8)) * DAY, checked ? o.start + 12 * MIN : null);
      db.prepare('INSERT OR IGNORE INTO gathering_rsvp_awards (gathering_id,user_id) VALUES (?,?)').run(id, u);
    });
    (o.votes || []).forEach((u, k) => db.prepare('INSERT OR IGNORE INTO gathering_votes (gathering_id,user_id,created_at) VALUES (?,?,?)').run(id, u, t0 - (k + 1) * HOUR));
    return id;
  };
  const allCit = [...people, demo2];
  const day = (n, hr = 7) => { const d = new Date(t0 + n * DAY); d.setHours(hr, 0, 0, 0); return d.getTime(); };

  mkG('plant', { title: 'Sunday Plantation Drive at Telibandha Lake', type: 'plantation', d: [0.006, -0.004], address: 'Telibandha Lake, Raipur',
    description: 'We will plant 200 native saplings along the eastern edge of Telibandha talab. Saplings, tree guards and water are provided. Please wear closed shoes and bring a cap.',
    start: day(2, 7), end: day(2, 10), org: people[1], club: clubGreen, cap: 40, going: allCit.slice(0, 12), media: ph('plantation', 0, 1) });
  mkG('run', { title: 'Raipur Run 5K: Run for Clean Air', type: 'marathon', d: [-0.002, 0.008], address: 'Marine Drive start line, Raipur',
    description: 'A timed 5K run along Marine Drive with a separate 2K family walk. Every finisher gets a medal and there are water points every 1.5 km.',
    start: day(4, 6), end: day(4, 9), org: people[0], club: clubRun, going: [...allCit.slice(0, 7), demo], media: ph('marathon', 0, 1) });
  mkG('blood', { title: 'Blood Donation Camp for Thalassemia Patients', type: 'blood', d: [0.01, 0.006], address: 'Community Hall, Shankar Nagar',
    description: 'A mobile blood bank van and doctors from the district hospital will be on site. Please eat well before donating and carry a photo ID.',
    start: day(6, 9), end: day(6, 15), org: seva, club: clubBlood, cap: 60, going: [people[0], people[2], people[5], people[11], demo2], media: ph('blood', 0, 1) });
  mkG('stray', { title: 'Stray Care: Vaccination and Feeding Day', type: 'animal_care', d: [-0.006, -0.002], address: 'Pandri Park, Raipur',
    description: 'A veterinary team will vaccinate strays in and around Pandri Park while volunteers feed and ear-tag them. We are limiting this to 12 volunteers so the animals are not stressed.',
    start: day(3, 8), end: day(3, 12), org: people[3], club: clubStray, cap: 12, going: people.slice(0, 12), media: ph('animal', 1, 2) });
  mkG('lake', { title: 'Lake Clean-up Saturday', type: 'cleanup', d: [0.004, -0.008], address: 'Budha Talab, Raipur',
    description: 'Gloves, bags and tea are provided. We will clear plastic from the water and the banks near the Budha talab ghat.',
    start: day(5, 7), end: day(5, 10), org: people[5], club: clubLake, cap: 50, going: [people[1], people[4], people[5], people[7], people[9], demo, demo2], media: ph('cleanup', 0, 1) });
  mkG('kitchen', { title: 'Community Kitchen: Serve a Hot Meal', type: 'food_drive', d: [0.0008, 0.0006], address: 'Near Telibandha Chowk, Raipur',
    description: 'We are cooking and serving about 150 hot meals to daily-wage workers near the chowk. You can join any time in the next two hours.',
    start: t0 - 30 * MIN, end: t0 + 150 * MIN, org: people[2], going: [people[2], people[4], people[6], people[8], people[10], people[11]], media: ph('food', 0) });
  mkG('shelter', { title: 'Visit to Asha Shelter Home', type: 'shelter', d: [-0.011, 0.012], address: 'Asha Shelter Home, Devendra Nagar',
    description: 'An afternoon with the elderly residents of the home: carrom, bhajans and a shared lunch. Please bring a book or a song to share.',
    start: day(9, 15), end: day(9, 18), org: seva, cap: 25, going: [people[3], people[9], demo2], media: ph('shelter', 0, 1) });
  mkG('health', { title: 'Free Health Checkup Camp, Telibandha Ward', type: 'health', d: [0.012, -0.014], address: 'Ward Office Grounds, Telibandha',
    description: 'Blood pressure, sugar, eye and dental screening for all residents, organised by the ward office with local doctors. No registration is needed.',
    start: day(12, 9), end: day(12, 14), org: neta, going: [people[0], people[5], people[8]], media: ph('health', 0, 1) });
  mkG('orphan-visit', { title: 'Sunday Visit to Bal Vikas Anathalaya', type: 'shelter', d: [-0.058, -0.249], address: 'Bal Vikas Anathalaya, Sector 6, Bhilai',
    description: 'Spend the afternoon with 54 children: storytelling, drawing and a shared snack. Please bring a storybook or a game, and wear something bright.',
    start: day(3, 15), end: day(3, 18), org: bal, cap: 30, going: [people[0], people[3], people[6], people[8], people[10], demo, demo2], media: ph('shelter', 2) });
  mkG('health-elder', { title: 'Free Health Camp for Senior Citizens, Durg', type: 'health', d: [-0.04, -0.31], address: 'Shanti Vridhashram, Padmanabhpur, Durg',
    description: 'Blood pressure, sugar, eye and bone-density screening with volunteer doctors, plus free reading glasses for those who need them. Residents and neighbours above 60 are welcome.',
    start: day(7, 9), end: day(7, 13), org: vri, cap: 120, going: [people[1], people[2], people[5], people[7], people[9], people[11], demo], media: ph('health', 2, 0) });
  mkG('dinner-drive', { title: 'Dinner for 60 at Raen Basera Night Shelter', type: 'food_drive', d: [-0.017, 0.004], address: 'Raen Basera Night Shelter, Station Road, Raipur',
    description: 'We are collecting cooked dinner for 60 residents and will serve it together at 8 pm. Volunteers are needed to pack, carry and serve between 6 and 9 pm.',
    start: day(1, 18), end: day(1, 21), org: ras, cap: 20, going: [people[4], people[6], people[10], demo2], media: ph('food', 1) });
  mkG('past-orphan', { title: 'Diwali Sweets at Bal Vikas Anathalaya', type: 'shelter', d: [-0.058, -0.249], address: 'Bal Vikas Anathalaya, Sector 6, Bhilai', status: 'completed',
    description: 'Volunteers brought sweets, new clothes and fireworks-free sparklers for the children.', start: day(-12, 16), end: day(-12, 19), org: bal, going: [people[0], people[3], people[8], demo],
    checked: [people[0], people[3], people[8], demo], impact: '54 children received new clothes and a festival meal.', media: ph('shelter', 0) });
  mkG('p-trees', { title: 'Plant 1,000 saplings along the Ring Road', type: 'plantation', d: [0.02, 0.02], address: 'Ring Road, Raipur', status: 'proposed',
    description: 'A proposal to line the Ring Road with shade trees such as neem and karanj. It needs 5 votes to go ahead.',
    start: day(20, 7), end: day(20, 11), org: people[7], club: clubGreen, votes: [people[1], people[2], people[3]], media: ph('plantation', 2) });
  mkG('p-blanket', { title: 'Winter Blanket Drive for the Homeless', type: 'other', d: [-0.008, 0.004], address: 'Railway Station Road, Raipur', status: 'proposed',
    description: 'Collect and hand out 300 blankets near the railway station on the coldest night of the month. One more vote makes it official.',
    start: day(15, 19), end: day(15, 22), org: people[9], votes: [people[0], people[4], people[6], people[10]], media: ph('clothes', 0) });
  mkG('p-cycle', { title: 'Weekly Sunday Cycle Rally', type: 'marathon', d: [0.003, 0.003], address: 'Capital Complex, Raipur', status: 'proposed',
    description: 'An easy-paced group ride every Sunday morning from Capital Complex. Vote if you would join regularly.', start: day(25, 6), end: day(25, 8), org: demo, votes: [people[5]], media: ph('marathon', 2) });
  const pastC = [demo, ...people.slice(1, 9), demo2];
  mkG('past-lake', { title: 'Telibandha Lake Clean-up', type: 'cleanup', d: [0.006, -0.005], address: 'Telibandha Lake, Raipur', status: 'completed',
    description: 'Our biggest clean-up so far, covering the north and east banks.', start: day(-9, 7), end: day(-9, 11), org: demo, club: clubLake, going: [demo, ...people, demo2], checked: pastC,
    impact: 'Pulled out 40 sacks of plastic and cleared the north bank.', media: ph('cleanup', 2, 0) });
  mkG('past-plant', { title: 'Monsoon Plantation: 150 Saplings', type: 'plantation', d: [0.009, 0.001], address: 'Shankar Nagar Park', status: 'completed',
    description: 'Neem, peepal and arjun saplings planted with tree guards.', start: day(-20, 7), end: day(-20, 10), org: people[1], club: clubGreen,
    going: [demo, ...people.slice(1, 9)], checked: [demo, ...people.slice(1, 7)], impact: '150 saplings planted, each with a guard and a volunteer to water it.', media: ph('plantation', 1) });
  mkG('past-blood', { title: 'Blood Camp: 48 Units Collected', type: 'blood', d: [0.002, 0.012], address: 'Mowa Community Hall', status: 'completed',
    description: 'Thank you to everyone who donated.', start: day(-14, 9), end: day(-14, 15), org: seva, club: clubBlood, going: [people[0], people[2], people[5], people[11]],
    checked: [people[0], people[2], people[5], people[11]], impact: '48 units collected for the district blood bank.', media: ph('blood', 2) });
  mkG('past-10k', { title: 'City 10K Run', type: 'marathon', d: [-0.003, 0.009], address: 'Marine Drive', status: 'completed',
    description: 'The club\'s first 10K.', start: day(-30, 6), end: day(-30, 9), org: people[0], club: clubRun, going: [people[0], people[1], people[4], people[8], demo],
    checked: [people[0], people[1], people[4], demo], impact: '120 runners finished and raised Rs 60,000 for stray animal care.', media: ph('marathon', 1) });
  mkG('past-pandri', { title: 'Pandri Market Clean-up', type: 'cleanup', d: [-0.002, 0.002], address: 'Pandri Market', status: 'completed',
    description: 'Clean-up of the market lanes and the drain behind the fish market.', start: day(-40, 7), end: day(-40, 10), org: people[5], club: clubLake, going: [demo, people[1], people[5], people[9]],
    checked: [demo, people[1], people[5]], impact: 'Market lanes cleared and 12 new bins installed by the ward office.', media: ph('garbage', 1) });
  mkG('cancelled', { title: 'Poster Making Workshop', type: 'other', d: [0.001, -0.001], address: 'Ward Library', status: 'cancelled',
    description: 'Cancelled because the venue was not available.', start: day(7, 16), end: day(7, 18), org: people[10], going: [people[2]] });

  // ----- donations -----
  const dIds = {};
  const mkD = (key, o) => {
    const created = t0 - (o.createdMinAgo ?? 30) * MIN;
    const prepared = o.kind === 'food' ? t0 - (o.preparedMinAgo ?? 60) * MIN : null;
    const expires = o.expiresAt ?? (o.kind === 'food' ? prepared + CONFIG.foodShelfHours * HOUR : created + CONFIG.otherShelfDays * DAY);
    const id = Number(db.prepare(`INSERT INTO donations (kind,title,description,quantity,servings,veg,prepared_at,expires_at,lat,lng,address,pickup_note,media,hygiene_ack,donor_id,status,
        claimed_by,claimed_at,eta_at,lock_expires_at,picked_up_at,distributed_at,dist_note,dist_beneficiaries,dist_media,created_at)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`)
      .run(o.kind, o.title, o.description || '', o.quantity, o.servings ?? null, o.veg || 'na', prepared, expires,
        BASE.lat + o.d[0], BASE.lng + o.d[1], o.address, o.pickup || null, JSON.stringify(o.media || []), o.kind === 'food' ? 1 : 0, o.donor,
        o.status || 'available', o.by ?? null, o.claimedAt ?? null, o.etaAt ?? null, o.lockAt ?? null, o.pickedAt ?? null, o.distAt ?? null,
        o.distNote ?? null, o.beneficiaries ?? null, JSON.stringify(o.distMedia || []), created).lastInsertRowid);
    dIds[key] = id;
    const dh = (status, note, at, uid) => db.prepare('INSERT INTO donation_history (donation_id,status,note,user_id,created_at) VALUES (?,?,?,?,?)').run(id, status, note, uid, at);
    dh('available', 'Listed for donation', created, o.donor);
    if (o.by) dh('claimed', 'Claimed for pickup', o.claimedAt, o.by);
    if (o.pickedAt) dh('picked_up', 'Picked up', o.pickedAt, o.by);
    if (o.distAt) dh('distributed', `Reached ${o.beneficiaries} people`, o.distAt, o.by);
    if (o.status === 'expired') dh('expired', 'Nobody collected it in time', expires, null);
    if (o.status === 'cancelled') dh('cancelled', 'Cancelled by the donor', created + 20 * MIN, o.donor);
    return id;
  };
  mkD('critical', { kind: 'food', title: 'Wedding leftovers: dal, rice and sabzi', quantity: '6 large containers', servings: 80, veg: 'veg', preparedMinAgo: 200,
    d: [0.006, 0.008], address: 'Lawn 4, Civil Lines Banquet, Raipur', pickup: 'Ask for Manoj at the kitchen gate.', donor: people[4], media: ph('thali', 0), description: 'Cooked for last night\'s reception and kept covered in the kitchen. It needs to reach people within the next hour or two.' });
  mkD('lunch', { kind: 'food', title: 'Office canteen: veg lunch packets', quantity: '45 packets', servings: 45, veg: 'veg', preparedMinAgo: 150,
    d: [0.003, -0.003], address: 'Capital Complex canteen, Raipur', donor: demo, media: ph('thali', 1), description: 'Packed lunches left over after a training session was cancelled. They are sealed and have been kept in the canteen fridge.' });
  mkD('snacks', { kind: 'food', title: 'Birthday party snacks and sweets', quantity: '3 trays', servings: 30, veg: 'veg', preparedMinAgo: 60,
    d: [-0.004, 0.005], address: 'Mowa Road, Raipur', donor: people[8], media: ph('thali', 2) });
  mkD('jackets', { kind: 'clothes', title: 'Winter jackets and sweaters', quantity: '25 pieces', d: [0.008, -0.01], address: 'Telibandha, Raipur', donor: people[5], media: ph('clothes', 0, 1),
    description: 'Washed and folded, in adult and children\'s sizes.', createdMinAgo: 300 });
  mkD('books', { kind: 'books', title: 'School storybooks and workbooks', quantity: '60 books', d: [-0.007, -0.006], address: 'Pandri, Raipur', donor: people[10], media: ph('books', 0, 1), createdMinAgo: 600 });
  mkD('bottles', { kind: 'bottles', title: 'Reusable steel water bottles', quantity: '40 bottles', d: [0.012, 0.004], address: 'Shankar Nagar, Raipur', donor: neta, media: ph('ngo', 2), createdMinAgo: 120,
    description: 'Left over from a ward campaign. Useful for schools and shelters.' });
  mkD('toys', { kind: 'toys', title: 'Toys in good condition', quantity: '2 bags', d: [0.001, 0.014], address: 'Mowa, Raipur', donor: demo2, media: ph('toys', 0, 1), createdMinAgo: 1500 });
  mkD('kits', { kind: 'essentials', title: 'Ration kits: rice, dal and oil', quantity: '15 kits', d: [-0.012, 0.003], address: 'Devendra Nagar, Raipur', donor: people[0], media: ph('food', 3), createdMinAgo: 90 });
  mkD('claimed-seva', { kind: 'food', title: 'Hotel buffet leftovers', quantity: '8 containers', servings: 60, veg: 'mixed', preparedMinAgo: 100, d: [0.005, 0.002],
    address: 'Hotel Grand Plaza, Raipur', donor: people[2], media: ph('food', 0), status: 'claimed', by: seva, claimedAt: t0 - 12 * MIN, etaAt: t0 + 20 * MIN, lockAt: t0 + 33 * MIN });
  mkD('claimed-anna', { kind: 'food', title: 'Bakery bread and buns', quantity: '50 packs', servings: 50, veg: 'veg', preparedMinAgo: 90, d: [-0.003, -0.002],
    address: 'City Bakery, Pandri', donor: people[6], media: ph('food', 1), status: 'claimed', by: anna, claimedAt: t0 - 5 * MIN, etaAt: t0 + 30 * MIN, lockAt: t0 + 40 * MIN });
  mkD('pickedup', { kind: 'food', title: 'Community feast biryani', quantity: '10 degchis', servings: 100, veg: 'nonveg', preparedMinAgo: 150, d: [0.002, 0.009],
    address: 'Mowa Community Hall', donor: people[9], media: ph('food', 2), status: 'picked_up', by: anna, claimedAt: t0 - 40 * MIN, etaAt: t0 - 20 * MIN, pickedAt: t0 - 10 * MIN });
  mkD('dist-1', { kind: 'food', title: 'Temple prasad and khichdi', quantity: '5 containers', servings: 120, veg: 'veg', preparedMinAgo: 27 * 60, d: [0.004, 0.004],
    address: 'Shankar Nagar Temple', donor: people[1], status: 'distributed', by: anna, claimedAt: t0 - 26 * HOUR, etaAt: t0 - 25 * HOUR, pickedAt: t0 - 25 * HOUR, distAt: t0 - 24 * HOUR,
    distNote: 'Served at the night shelter near the railway station.', beneficiaries: 110, distMedia: ph('food', 0), createdMinAgo: 27 * 60, expiresAt: t0 - 23 * HOUR });
  mkD('dist-clothes', { kind: 'clothes', title: 'Children\'s school uniforms', quantity: '30 sets', d: [0.01, 0.0], address: 'Telibandha, Raipur', donor: demo, status: 'distributed', by: seva,
    claimedAt: t0 - 3 * DAY, etaAt: t0 - 3 * DAY + HOUR, pickedAt: t0 - 3 * DAY + 2 * HOUR, distAt: t0 - 2 * DAY, distNote: 'Handed to families at the ward school.', beneficiaries: 28, distMedia: ph('clothes', 1), createdMinAgo: 4 * 24 * 60 });
  [['dist-2', 'Canteen dal-roti trays', seva, 70, 0], ['dist-3', 'Society event lunch', anna, 90, 1], ['dist-4', 'Marriage hall dinner', seva, 150, 2], ['dist-5', 'School fete snacks', anna, 40, 3]].forEach(([k, title, by, ben, n]) => {
    mkD(k, { kind: 'food', title, quantity: '4 containers', servings: ben + 10, veg: 'veg', preparedMinAgo: (5 + n * 2) * 24 * 60, d: [0.002 * n, -0.002], address: ['Civil Lines, Raipur', 'Samta Colony, Raipur', 'Fafadih, Raipur', 'Kota, Raipur'][n], donor: people[1],
      status: 'distributed', by, claimedAt: t0 - (5 + n * 2) * DAY, etaAt: t0 - (5 + n * 2) * DAY + HOUR, pickedAt: t0 - (5 + n * 2) * DAY + 90 * MIN, distAt: t0 - (5 + n * 2) * DAY + 3 * HOUR,
      distNote: 'Served at a community kitchen to families from nearby bastis.', beneficiaries: ben, createdMinAgo: (5 + n * 2) * 24 * 60, expiresAt: t0 - (4 + n * 2) * DAY });
  });
  mkD('rest-biryani', { kind: 'food', title: 'Restaurant surplus: veg pulao and dal tadka', quantity: '5 containers', servings: 55, veg: 'veg', preparedMinAgo: 25, createdMinAgo: 10,
    d: [0.009, -0.006], address: 'Rajdhani Restaurant, Jaistambh Chowk, Raipur', pickup: 'Back entrance, ask for the manager.', donor: people[8], media: ph('thali', 3),
    description: 'Freshly cooked for the lunch rush and not sold. Packed in covered steel containers.' });
  mkD('caterer-dinner', { kind: 'food', title: 'Caterer surplus: paneer, roti and rice for 70', quantity: '7 trays', servings: 70, veg: 'veg', preparedMinAgo: 40, createdMinAgo: 15,
    d: [-0.015, 0.006], address: 'Shree Caterers, Station Road, Raipur', pickup: 'Pickup before 9 pm from the loading bay.', donor: people[6], media: ph('food', 2),
    description: 'Prepared for a corporate dinner with fewer guests than booked. Kept hot and covered.' });
  mkD('blankets', { kind: 'clothes', title: 'Blankets and quilts, washed', quantity: '22 blankets', d: [-0.005, 0.01], address: 'Fafadih, Raipur', donor: people[3], media: ph('clothes', 2), createdMinAgo: 200,
    description: 'Clean woollen blankets and a few quilts. Good for the night shelter or an old-age home.' });
  mkD('meds', { kind: 'medicine', title: 'Unopened vitamins and first-aid supplies', quantity: '1 box', d: [0.004, 0.011], address: 'Shankar Nagar, Raipur', donor: people[5], media: ph('health', 0), createdMinAgo: 400,
    description: 'Sealed and well within expiry: multivitamins, bandages and antiseptic. No prescription drugs.' });
  mkD('stationery', { kind: 'stationery', title: 'Notebooks, pens and geometry boxes', quantity: '80 notebooks, 40 pens', d: [0.001, -0.016], address: 'Civil Lines, Raipur', donor: people[11], media: ph('books', 2), createdMinAgo: 800 });
  mkD('dist-blankets', { kind: 'clothes', title: 'Winter blankets for the old-age home', quantity: '35 blankets', d: [0.007, 0.002], address: 'Samta Colony, Raipur', donor: people[0], media: ph('clothes', 0), status: 'distributed', by: vri,
    claimedAt: t0 - 5 * DAY, etaAt: t0 - 5 * DAY + HOUR, pickedAt: t0 - 5 * DAY + 2 * HOUR, distAt: t0 - 4 * DAY, distNote: 'Every resident now has a blanket for the winter. Handed over with tea and a short bhajan evening.',
    beneficiaries: 38, distMedia: ph('shelter', 1), createdMinAgo: 6 * 24 * 60 });
  mkD('dist-dinner', { kind: 'food', title: 'Wedding dinner for the night shelter', quantity: '9 containers', servings: 90, veg: 'veg', preparedMinAgo: 12 * 60, d: [0.003, 0.007], address: 'Civil Lines Banquet, Raipur',
    donor: people[4], media: ph('thali', 1), status: 'distributed', by: ras, claimedAt: t0 - 11 * HOUR, etaAt: t0 - 10 * HOUR, pickedAt: t0 - 10 * HOUR, distAt: t0 - 9 * HOUR,
    distNote: 'Served hot to 85 residents and 12 families waiting at the hospital.', beneficiaries: 85, distMedia: ph('food', 1), createdMinAgo: 12 * 60, expiresAt: t0 - 8 * HOUR });
  mkD('dist-stationery', { kind: 'stationery', title: 'Braille slates and notebooks', quantity: '25 sets', d: [-0.009, -0.02], address: 'Kota, Raipur', donor: demo, media: ph('books', 1), status: 'distributed', by: drs,
    claimedAt: t0 - 9 * DAY, etaAt: t0 - 9 * DAY + HOUR, pickedAt: t0 - 9 * DAY + 2 * HOUR, distAt: t0 - 8 * DAY, distNote: 'Given to students in the Class 6 to 8 Braille batch.', beneficiaries: 25,
    distMedia: ph('books', 0), createdMinAgo: 10 * 24 * 60 });
  mkD('dist-bal', { kind: 'food', title: 'School canteen khichdi and fruit', quantity: '6 containers', servings: 60, veg: 'veg', preparedMinAgo: 30 * 60, d: [-0.058, -0.249], address: 'Sector 6, Bhilai',
    donor: demo, media: ph('thali', 0), status: 'distributed', by: bal, claimedAt: t0 - 29 * HOUR, etaAt: t0 - 28 * HOUR, pickedAt: t0 - 28 * HOUR, distAt: t0 - 27 * HOUR,
    distNote: 'Dinner for all 54 children at the anathalaya, with fruit for tomorrow.', beneficiaries: 54, distMedia: ph('food', 3), createdMinAgo: 30 * 60, expiresAt: t0 - 26 * HOUR });
  mkD('expired-food', { kind: 'food', title: 'Catering surplus nobody collected', quantity: '6 trays', servings: 50, veg: 'mixed', preparedMinAgo: 6 * 60, d: [0.007, -0.007],
    address: 'Sunder Nagar, Raipur', donor: people[7], status: 'expired', createdMinAgo: 6 * 60, expiresAt: t0 - 2 * HOUR });
  mkD('expired-books', { kind: 'books', title: 'Old exam guides', quantity: '30 books', d: [-0.006, 0.01], address: 'Gudhiyari, Raipur', donor: people[11], status: 'expired',
    createdMinAgo: 9 * 24 * 60, expiresAt: t0 - 2 * DAY });
  mkD('cancelled', { kind: 'food', title: 'Sweet boxes', quantity: '12 boxes', servings: 24, veg: 'veg', preparedMinAgo: 70, d: [0.003, 0.003], address: 'Tatibandh, Raipur', donor: people[0],
    status: 'cancelled', createdMinAgo: 70, expiresAt: t0 + 170 * MIN });

  // ----- donor kinds: restaurants and caterers are surplus-food givers -----
  db.prepare("UPDATE donations SET donor_kind='restaurant' WHERE id IN (?,?,?)").run(dIds['rest-biryani'], dIds.critical, dIds['claimed-seva']);
  db.prepare("UPDATE donations SET donor_kind='caterer' WHERE id IN (?,?,?)").run(dIds['caterer-dinner'], dIds['dist-dinner'], dIds.pickedup);

  // ----- needs: what verified foundations are asking for, with pledged progress -----
  const mkN = (o) => {
    const id = Number(db.prepare(`INSERT INTO needs (foundation_id,kind,title,quantity,deadline_at,status,created_at,urgency,description,target_qty,pledged_qty,unit)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`).run(o.f, o.kind, o.title, o.quantity, o.deadline ?? null, o.status || 'open', t0 - (o.ageH ?? 12) * HOUR,
      o.urgency || 'normal', o.description || '', o.target || 0, o.base || 0, o.unit || '').lastInsertRowid);
    (o.pledges || []).forEach(([u, qty, note], k) => db.prepare('INSERT OR IGNORE INTO need_pledges (need_id,user_id,note,created_at,qty) VALUES (?,?,?,?,?)')
      .run(id, u, note || null, t0 - (k + 1) * 3 * HOUR, qty));
    return id;
  };
  const nId = {};
  nId.blankets = mkN({ f: vri, kind: 'clothes', title: '40 blankets by Friday', quantity: '40 blankets', unit: 'blankets', target: 40, base: 12, urgency: 'critical', deadline: day(3, 17), ageH: 20,
    description: 'Nights in Durg are dropping below 10 degrees and 14 residents still sleep under thin sheets. Clean, used blankets are fine.',
    pledges: [[people[3], 10, 'I can send 10 from the shop on Thursday'], [people[5], 4]] });
  nId.dinner = mkN({ f: ras, kind: 'food', title: 'Dinner for 60 residents', quantity: '60 plates', unit: 'plates', target: 60, base: 0, urgency: 'high', deadline: day(1, 20), ageH: 6,
    description: 'Our kitchen gas cylinder ran out and the refill is delayed. Cooked veg dinner delivered by 8 pm would feed everyone tonight.',
    pledges: [[people[6], 30, 'Our caterer can send 30 plates']] });
  nId.clothes = mkN({ f: bal, kind: 'clothes', title: 'Winter clothes for 54 children', quantity: '54 sets', unit: 'sets', target: 54, base: 20, urgency: 'high', deadline: day(8, 12), ageH: 48,
    description: 'Sweaters, caps and socks for children aged 4 to 17. Sizes are needed across the range, and new or gently used are both welcome.',
    pledges: [[people[0], 15], [demo2, 6, 'Collecting from my apartment society']] });
  nId.meds = mkN({ f: vri, kind: 'medicine', title: 'Monthly BP and diabetes medicines', quantity: '30 strips', unit: 'strips', target: 30, base: 8, urgency: 'critical', deadline: day(2, 18), ageH: 30,
    description: 'Amlodipine and metformin for 22 residents. Please send only sealed strips with at least six months to expiry, and a pharmacy bill if you have one.',
    pledges: [[people[8], 8, 'I will buy these at the Jaistambh pharmacy']] });
  nId.stationery = mkN({ f: bal, kind: 'stationery', title: 'Notebooks and pens for the new term', quantity: '150 notebooks', unit: 'notebooks', target: 150, base: 40, urgency: 'normal', deadline: day(14, 12), ageH: 72,
    description: 'The new session starts in two weeks. Ruled notebooks, pens, pencils and geometry boxes for classes 1 to 10.',
    pledges: [[people[11], 80, 'Posting from the Civil Lines stock'], [demo, 20]] });
  nId.scribes = mkN({ f: drs, kind: 'volunteers', title: '6 volunteers to read and scribe on Saturday', quantity: '6 people', unit: 'people', target: 6, base: 2, urgency: 'high', deadline: day(5, 8), ageH: 36,
    description: 'Our students have a mock exam on Saturday morning and need scribes and readers for three hours. No special training needed.',
    pledges: [[people[7], 1], [people[9], 1]] });
  nId.money = mkN({ f: drs, kind: 'money', title: 'Rs 25,000 for 10 audio-book players', quantity: 'Rs 25,000', unit: 'rupees', target: 25000, base: 9000, urgency: 'normal', deadline: day(20, 12), ageH: 100,
    description: 'Each player costs Rs 2,500 and carries a full term of audio textbooks. Any amount helps and we publish every receipt.',
    pledges: [[people[2], 5000, 'Happy to cover two players'], [people[10], 2000]] });
  nId.food = mkN({ f: seva, kind: 'food', title: 'Rice, dal and oil for the community kitchen', quantity: '100 kg', unit: 'kg', target: 100, base: 35, urgency: 'normal', deadline: day(6, 17), ageH: 60,
    description: 'Stock for the next fortnight of hot meals at the Shankar Nagar kitchen.', pledges: [[people[0], 25], [people[4], 15]] });
  nId.stationeryAnna = mkN({ f: anna, kind: 'essentials', title: 'Steel plates and glasses for evening meals', quantity: '120 sets', unit: 'sets', target: 120, base: 30, urgency: 'low', ageH: 90,
    description: 'We are replacing disposable plates with steel ones at all four serving points.', pledges: [[people[1], 20]] });
  nId.done = mkN({ f: ras, kind: 'clothes', title: '30 warm jackets for night-shelter guests', quantity: '30 jackets', unit: 'jackets', target: 30, base: 30, urgency: 'high', status: 'fulfilled', ageH: 200,
    description: 'Fulfilled last week, thank you to everyone who pledged.', pledges: [[demo, 10], [people[5], 20]] });

  // ----- likes -----
  const like = (type, id, u) => db.prepare('INSERT OR IGNORE INTO likes (target_type,target_id,user_id,created_at) VALUES (?,?,?,?)').run(type, id, u, t0 - Math.floor(rnd() * 5 * DAY));
  const everyone = [demo, demo2, ...people, neta, admin, seva, anna];
  const issueIds = db.prepare('SELECT id FROM issues ORDER BY id').all().map((r) => r.id);
  for (const id of issueIds) {
    const k = Math.floor(rnd() * 6);
    for (let j = 0; j < k; j++) like('issue', id, pick(everyone));
    if (rnd() < 0.2) db.prepare('UPDATE issues SET share_count=? WHERE id=?').run(1 + Math.floor(rnd() * 5), id);
  }
  [i6, i2, i1, i4, i3].forEach((id) => everyone.slice(0, 10).forEach((u) => like('issue', id, u)));
  db.prepare('UPDATE issues SET share_count=14 WHERE id=?').run(i6);
  db.prepare('UPDATE issues SET share_count=9 WHERE id=?').run(i2);
  for (const id of Object.values(gids)) everyone.slice(0, 2 + Math.floor(rnd() * 8)).forEach((u) => like('gathering', id, u));
  for (const id of Object.values(dIds)) everyone.slice(2, 4 + Math.floor(rnd() * 6)).forEach((u) => like('donation', id, u));
  db.prepare('UPDATE gatherings SET share_count=? WHERE id=?').run(11, gids.plant);
  db.prepare('UPDATE gatherings SET share_count=? WHERE id=?').run(7, gids.run);
  db.prepare('UPDATE donations SET share_count=? WHERE id=?').run(6, dIds.critical);

  // ----- comments -----
  let ck = 0;
  const comment = (type, id, u, body, hoursAgo, m = []) =>
    db.prepare('INSERT INTO comments (target_type,target_id,user_id,body,media,created_at) VALUES (?,?,?,?,?,?)').run(type, id, u, body, JSON.stringify(m), t0 - (hoursAgo + (ck++ % 3)) * HOUR);
  comment('issue', i6, people[1], 'I went past this morning. Two bikes skidded while I was standing there.', 30);
  comment('issue', i6, neta, 'I have raised this with the zone office and it is now on the authority portal. Thank you all for the photos.', 28);
  comment('issue', i6, admin, 'Received. The Public Works team will survey the site this week.', 20);
  comment('issue', i6, people[3], 'Any update? The vegetable sellers are losing business every morning.', 5);
  comment('issue', i2, people[8], 'My daughter walks past this every day. Please cover it soon.', 40);
  comment('issue', i2, neta, 'Escalated. This is a safety hazard next to a school.', 29);
  comment('issue', i1, people[4], 'It is completely dark after 7 pm. Please fix it soon.', 60);
  comment('issue', i1, admin, 'A survey team will be there tomorrow morning.', 48);
  comment('issue', i3, people[0], 'The truck came yesterday. Thank you.', 12);
  comment('issue', i4, demo, 'It looks dry now. I will verify on my way home.', 3);
  comment('issue', i5, people[5], 'The new benches are a big improvement.', 190);
  comment('gathering', gids.plant, people[2], 'Can we bring our own saplings as well?', 20);
  comment('gathering', gids.plant, people[1], 'Yes, please do. We will have tree guards for all of them.', 18);
  comment('gathering', gids.run, people[4], 'Is there a pace group for slower runners?', 12);
  comment('gathering', gids.run, people[0], 'Yes, a 7 minutes per km group starts last.', 11);
  comment('gathering', gids.stray, people[6], 'I will bring 5 kg of dog food.', 9);
  comment('gathering', gids['p-blanket'], people[4], 'I can donate 20 blankets from the shop.', 8);
  comment('gathering', gids['past-lake'], people[1], 'Good turnout. Thank you everyone who came.', 24 * 8);
  comment('donation', dIds.critical, seva, 'On our way shortly, thank you for sharing.', 1);
  comment('donation', dIds.critical, people[4], 'Gate 2 is easier for vans.', 1);
  comment('donation', dIds.jackets, anna, 'We could use these at the night shelter. We will check with the donor.', 3);
  comment('donation', dIds['dist-1'], people[1], 'Good to see this reached people the same day.', 23);
  comment('donation', dIds.lunch, demo2, 'Good that someone is taking this up. Do you need help with transport?', 2);

  // ----- notifications for the new roles -----
  const nt = (u, type, title, body, refType, refId, ageH, issueId = null) =>
    db.prepare('INSERT INTO notifications (user_id,type,title,body,issue_id,read,created_at,ref_type,ref_id) VALUES (?,?,?,?,?,0,?,?,?)').run(u, type, title, body, issueId, t0 - ageH * HOUR, refType, refId);
  nt(admin, 'escalated', 'Escalated by an elected leader', 'Lakshmi Sahu escalated "Open manhole beside Telibandha chowk"', 'issue', i2, 30, i2);
  nt(admin, 'escalated', 'Escalated by an elected leader', 'Lakshmi Sahu escalated "Potholes outside Telibandha vegetable market"', 'issue', i6, 50, i6);
  nt(admin, 'foundation_verified', 'Foundation awaiting verification', 'New Hope Trust has registered and needs verification', null, null, 6);
  nt(neta, 'comment', 'New comment', 'Priya Dubey commented on "Potholes outside Telibandha vegetable market"', 'issue', i6, 20, i6);
  nt(neta, 'authority_update', 'Authority update', 'Water Supply marked "Burst water pipeline on Marine Drive" as fixed', 'issue', i4, 6, i4);
  nt(seva, 'donation', 'Donation near you', 'Wedding leftovers: dal, rice and sabzi is available and will not keep for long', 'donation', dIds.critical, 0.5);
  nt(seva, 'donation', 'Donation near you', 'Winter jackets and sweaters is available', 'donation', dIds.jackets, 4);
  nt(anna, 'donation', 'Donation near you', 'Wedding leftovers: dal, rice and sabzi is available and will not keep for long', 'donation', dIds.critical, 0.5);
  nt(anna, 'donation', 'Donation near you', 'Birthday party snacks and sweets is available', 'donation', dIds.snacks, 1);
  nt(vri, 'need_pledge', 'Someone pledged to your need', 'Poonam Yadav pledged to help with "40 blankets by Friday"', 'need', nId.blankets, 5);
  nt(ras, 'need_pledge', 'Someone pledged to your need', 'Ramesh Chandrakar pledged to help with "Dinner for 60 residents"', 'need', nId.dinner, 2);
  nt(seva, 'donation', 'Surplus food near you', 'Restaurant surplus: veg pulao and dal tadka is available and will not keep for long', 'donation', dIds['rest-biryani'], 0.2);
  nt(demo, 'authority_update', 'Authority says it is fixed', 'Please verify "Burst water pipeline on Marine Drive" if you are nearby', 'issue', i4, 6, i4);
  nt(demo, 'donation_distributed', 'Your donation made a difference', '"Children\'s school uniforms" reached 28 people via Seva Sankalp Foundation. You earned 10 points.', 'donation', dIds['dist-clothes'], 48);
  nt(demo, 'rsvp', 'New RSVP', 'Kiran Mahant is going to "Telibandha Lake Clean-up"', 'gathering', gids['past-lake'], 200);
  nt(demo, 'event_created', 'Your campaign needs votes', '"Weekly Sunday Cycle Rally" has 1 of 5 votes', 'gathering', gids['p-cycle'], 10);

  // anything still without media gets a photo that matches what it is
  const GTOPIC = { plantation: 'plantation', animal_care: 'animal', shelter: 'shelter', marathon: 'marathon', health: 'health', cleanup: 'cleanup', blood: 'blood', food_drive: 'food', other: 'ngo' };
  const DTOPIC = { food: 'thali', clothes: 'clothes', bottles: 'ngo', books: 'books', toys: 'toys', essentials: 'food', other: 'ngo' };
  db.prepare("SELECT id, type FROM gatherings WHERE media='[]'").all().forEach((g) =>
    db.prepare('UPDATE gatherings SET media=? WHERE id=?').run(JSON.stringify(ph(GTOPIC[g.type] || 'ngo', g.id)), g.id));
  db.prepare("SELECT id, kind, status FROM donations WHERE media='[]'").all().forEach((d) =>
    db.prepare('UPDATE donations SET media=? WHERE id=?').run(JSON.stringify(ph(DTOPIC[d.kind] || 'ngo', d.id)), d.id));
  db.prepare("SELECT id, kind FROM donations WHERE status='distributed' AND (dist_media IS NULL OR dist_media='[]')").all().forEach((d) =>
    db.prepare('UPDATE donations SET dist_media=? WHERE id=?').run(JSON.stringify(ph(DTOPIC[d.kind] || 'ngo', d.id + 1)), d.id));

  // points + badge evaluation for check-ins / donations / comments
  const pts = { [demo]: 15 * 4 + 10 * 2 + 20, [people[1]]: 15 * 4 + 10 * 5 };
  for (const u of [demo, demo2, ...people, neta, admin, seva, anna, hope, bal, vri, ras, drs]) award(u, pts[u] || 0, []);
  db.prepare('UPDATE users SET points = points + 120 WHERE id IN (?,?)').run(seva, anna);
}

if (process.argv[1] && process.argv[1].endsWith('seed.js')) {
  const pf = await prefetchPhotos((m) => process.stdout.write(`\r${m}          `));
  console.log(`\nPhotos: ${pf.fetched} downloaded, ${pf.cached} cached, ${pf.failed} failed${pf.offline ? ' (offline: using generated placeholders where missing)' : ''}`);
  seed();
  const c = (t, w = '') => db.prepare(`SELECT COUNT(*) c FROM ${t} ${w}`).get().c;
  console.log(`Seeded: ${c('areas', "WHERE kind='region'")} regions, ${c('areas', "WHERE kind='state'")} states, ${c('areas', "WHERE kind='city'")} cities, ${c('areas', "WHERE kind='ward'")} wards`);
  console.log(`        ${c('politicians')} leaders, ${c('users')} users, ${c('issues')} issues`);
  console.log(`        ${c('gatherings')} gatherings, ${c('clubs')} clubs, ${c('donations')} donations, ${c('comments')} comments`);
  console.log('SevaLink: needs=' + c('needs') + ', pledges=' + c('need_pledges') + ', foundations=' + c('users', "WHERE role='foundation'"));
  console.log('Demo logins: demo@bythepeople.app / demo1234 (citizen), admin@bythepeople.app / admin1234,');
  console.log('             neta@bythepeople.app / neta1234, seva@bythepeople.app / seva1234,');
  console.log('             annapurna@bythepeople.app / anna1234, newhope@bythepeople.app / hope1234 (unverified),');
  console.log('             balvikas@ / bal1234, vridhashram@ / vri1234, rainbasera@ / ras1234, drishti@ / drishti1234 (all @bythepeople.app, verified foundations)');
}
