import { db, resetSchema, tx } from './db.js';
import { hashPassword, now, DAY } from './util.js';
import { routeIssue, award } from './logic.js';

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

const TEMPLATES = {
  road: ['Deep pothole near the bus stand', 'Broken footpath tiles are a trip hazard', 'Road caved in after the monsoon', 'Missing speed breaker outside the school'],
  garbage: ['Garbage not collected for a week', 'Overflowing bin at the sabzi mandi corner', 'Illegal dumping beside the talab wall'],
  water: ['No water supply since Monday', 'Leaking main pipe flooding the lane', 'Muddy, smelly tap water'],
  drainage: ['Open nala overflowing onto the road', 'Blocked storm drain causes waterlogging', 'Manhole cover missing'],
  electricity: ['Frequent power cuts every evening', 'Sparking transformer needs urgent check'],
  streetlight: ['Street lights dead on the whole lane', 'Flickering lamp near the chowk'],
  safety: ['Unlit underpass feels unsafe at night', 'Stray cattle blocking the main road'],
  park: ['Playground swings are broken', 'Talab railing is damaged'],
  other: ['Unauthorised hoardings blocking the view'],
};

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

    const history = (issueId, status, note, userId, at) =>
      db.prepare('INSERT INTO status_history (issue_id,status,note,user_id,created_at) VALUES (?,?,?,?,?)').run(issueId, status, note, userId, at);

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
    const wards = db.prepare("SELECT * FROM areas WHERE kind='ward' ORDER BY id").all();
    const evenPeople = people.filter((_, k) => k % 2 === 0);
    for (const w of wards) {
      const { quality, count } = wardQuality.get(w.id);
      for (let i = 0; i < count; i++) {
        const cat = pick(cats);
        const lat = w.lat + jitter(0.014);
        const lng = w.lng + jitter(0.014);
        const reporter = pick(people);
        const others = people.filter((p) => p !== reporter);
        if (rnd() < quality) {
          const age = 20 + Math.floor(rnd() * 70);
          const eventAt = now() - (age - 3) * DAY;
          const days = 4 + Math.floor(rnd() * 20);
          insertIssue({ lat, lng, category: cat, title: pick(TEMPLATES[cat]), reporter, supporters: others.slice(0, 5 + Math.floor(rnd() * 3)),
            volunteers: [pick(evenPeople)], status: 'closed', ageDays: age, eventAt, resolvedAt: eventAt + days * DAY, closedAt: eventAt + (days + 1) * DAY,
            note: 'Cleared and repaired by volunteers with the ward office', description: 'Reported by residents and resolved by the community.' });
        } else if (rnd() < 0.3) {
          const age = 3 + Math.floor(rnd() * 8);
          insertIssue({ lat, lng, category: cat, title: pick(TEMPLATES[cat]), reporter, supporters: others.slice(0, 5), status: 'event',
            ageDays: age, eventAt: now() - 1 * DAY, scheduledAt: now() + (1 + Math.floor(rnd() * 5)) * DAY,
            description: 'The community backed this. Volunteers are needed.' });
        } else {
          insertIssue({ lat, lng, category: cat, title: pick(TEMPLATES[cat]), reporter, supporters: others.slice(0, Math.floor(rnd() * 4)),
            status: 'open', ageDays: 1 + Math.floor(rnd() * 25), description: 'Please look into this. It has been affecting the whole neighbourhood.' });
        }
      }
    }

    // ---------- hand-made Raipur journey around the demo location ----------
    const evA = insertIssue({ lat: BASE.lat + 0.006, lng: BASE.lng + 0.004, category: 'garbage', title: 'Garbage dump behind Telibandha lake',
      description: 'Waste has been piling up for weeks. Volunteers needed for a safai abhiyan.', reporter: people[1],
      supporters: [people[2], people[3], people[4], people[5]], status: 'event', ageDays: 4, eventAt: now() - 1 * DAY, scheduledAt: now() + 2 * DAY });
    const evB = insertIssue({ lat: BASE.lat - 0.004, lng: BASE.lng - 0.006, category: 'road', title: 'Pothole cluster on Pandri Road',
      description: 'Six potholes in 200 m. Two bikes have already skidded.', reporter: people[6],
      supporters: [people[0], people[2], people[7], people[8]], volunteers: [people[0], demo],
      status: 'in_progress', ageDays: 6, eventAt: now() - 2 * DAY, scheduledAt: now() + 1 * DAY });
    insertIssue({ lat: BASE.lat + 0.01, lng: BASE.lng - 0.003, category: 'park', title: "Broken swings at the lakeside children's park",
      description: 'Children have nowhere safe to play. Fix needed.', reporter: people[3],
      supporters: [people[4], people[5], people[9], people[10]], volunteers: [people[4]], status: 'in_progress', ageDays: 9,
      eventAt: now() - 4 * DAY, scheduledAt: now() + 4 * DAY });
    const evD = insertIssue({ lat: BASE.lat + 0.002, lng: BASE.lng + 0.009, category: 'drainage', title: 'Blocked drain flooding Mowa Road',
      description: 'Water stands knee deep after every monsoon shower.', reporter: people[5],
      supporters: [demo, people[1], people[7], people[9]], volunteers: [people[8], people[10]],
      status: 'pending_verification', ageDays: 12, eventAt: now() - 8 * DAY, scheduledAt: now() - 2 * DAY,
      resolvedAt: now() - 1 * DAY, note: 'Drain desilted and the cover was replaced' });
    // 4 supporters: one more support triggers the event conversion
    insertIssue({ lat: BASE.lat + 0.0015, lng: BASE.lng + 0.001, category: 'streetlight', title: 'Street lights out on Shankar Nagar Road',
      description: 'The whole stretch has been dark for 10 days. Unsafe for evening walkers.', reporter: people[0],
      supporters: [people[2], people[4], people[6]], status: 'open', ageDays: 5 });
    insertIssue({ lat: BASE.lat - 0.002, lng: BASE.lng + 0.002, category: 'garbage', title: 'Overflowing bins at Pandri market',
      description: 'Smell is unbearable and stray animals are everywhere.', reporter: people[7],
      supporters: [people[1], people[3]], status: 'open', ageDays: 3 });
    insertIssue({ lat: BASE.lat + 0.003, lng: BASE.lng - 0.002, category: 'water', title: 'No water supply for 3 days in Devendra Nagar',
      description: 'Tankers are our only option. Please restore the pipeline.', reporter: people[9],
      supporters: [people[0], people[2], people[5]], status: 'open', ageDays: 3 });
    insertIssue({ lat: BASE.lat - 0.0035, lng: BASE.lng - 0.001, category: 'road', title: 'Missing speed breaker outside the school',
      description: 'Cars race past while children cross. A speed breaker is badly needed.', reporter: people[11],
      supporters: [people[8]], status: 'open', ageDays: 2 });
    // inside Raipur but far from the demo user: shows the distance gate
    insertIssue({ lat: BASE.lat + 0.03, lng: BASE.lng + 0.03, category: 'electricity', title: 'Sparking transformer near Tatibandh',
      description: 'Urgent safety risk. Cables are hanging low.', reporter: people[4],
      supporters: [people[2]], status: 'open', ageDays: 8 });

    // ---------- points, badges, notifications ----------
    people.forEach((p, i) => award(p, 40 + i * 35, []));
    award(demo, 62, []);
    award(demo2, 5, []);
    const n = (type, title, body, issueId, ageH) =>
      db.prepare('INSERT INTO notifications (user_id,type,title,body,issue_id,read,created_at) VALUES (?,?,?,?,?,?,?)')
        .run(demo, type, title, body, issueId, 0, now() - ageH * 3600000);
    n('event_nearby', 'New event near you', '"Garbage dump behind Telibandha lake" needs volunteers', evA, 20);
    n('verify_request', 'Is it really fixed?', 'Please verify "Blocked drain flooding Mowa Road" if you are nearby', evD, 5);
    n('event_scheduled', 'Event rescheduled', '"Pothole cluster on Pandri Road" is happening tomorrow', evB, 3);
  });
}

if (process.argv[1] && process.argv[1].endsWith('seed.js')) {
  seed();
  const c = (t, w = '') => db.prepare(`SELECT COUNT(*) c FROM ${t} ${w}`).get().c;
  console.log(`Seeded: ${c('areas', "WHERE kind='region'")} regions, ${c('areas', "WHERE kind='state'")} states, ${c('areas', "WHERE kind='city'")} cities, ${c('areas', "WHERE kind='ward'")} wards`);
  console.log(`        ${c('politicians')} leaders, ${c('users')} users, ${c('issues')} issues`);
  console.log('Demo login: demo@bythepeople.app / demo1234');
}
