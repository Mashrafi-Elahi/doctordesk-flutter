import { readFileSync } from 'node:fs';
import { after, afterEach, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, orderBy, query, setDoc, where } from 'firebase/firestore';

const projectId = 'doctordesk-rules-test';
const rules = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');
let testEnv;

const requestedAppointment = (overrides = {}) => ({
  userId: 'patient',
  patientName: 'Patient One',
  doctorId: 'doctor-profile',
  doctorName: 'Dr One',
  chamberId: 'chamber-a',
  status: 'requested',
  scheduledTime: new Date('2030-01-01T10:00:00Z'),
  createdAt: new Date('2030-01-01T09:00:00Z'),
  updatedAt: new Date('2030-01-01T09:00:00Z'),
  ...overrides,
});

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, 'users/patient'), { roles: {} }),
      setDoc(doc(db, 'users/doctor'), {
        roles: { isDoctor: true },
        doctorProfileId: 'doctor-profile',
      }),
      setDoc(doc(db, 'users/operator'), {
        roles: { isOperator: true },
        operatorAssignments: ['chamber-a'],
      }),
      setDoc(doc(db, 'users/stranger'), { roles: {} }),
      setDoc(doc(db, 'admins/admin'), { uid: 'admin' }),
    ]);
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules, host: '127.0.0.1', port: 8085 },
  });
  await seed();
});

afterEach(async () => {
  await testEnv.clearFirestore();
  await seed();
});

after(async () => {
  await testEnv.cleanup();
});

describe('appointment authorization', () => {
  it('allows a patient to request another doctor', async () => {
    const db = testEnv.authenticatedContext('patient').firestore();
    await assertSucceeds(setDoc(doc(db, 'appointments/patient-request'), requestedAppointment()));
  });

  it('prevents a doctor from requesting their own profile', async () => {
    const db = testEnv.authenticatedContext('doctor').firestore();
    await assertFails(setDoc(doc(db, 'appointments/doctor-self-request'), requestedAppointment({
      userId: 'doctor',
    })));
  });

  it('prevents an assigned operator from creating a requested appointment', async () => {
    const db = testEnv.authenticatedContext('operator').firestore();
    await assertFails(setDoc(doc(db, 'appointments/operator-request'), requestedAppointment({
      userId: 'operator',
    })));
  });

  it('allows an admin to create an appointment', async () => {
    const db = testEnv.authenticatedContext('admin').firestore();
    await assertSucceeds(setDoc(doc(db, 'appointments/admin-request'), requestedAppointment({
      userId: 'someone-else',
    })));
  });

  it('prevents a stranger from reading another patient appointment', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'appointments/private-request'), requestedAppointment());
    });
    const db = testEnv.authenticatedContext('stranger').firestore();
    await assertFails(getDoc(doc(db, 'appointments/private-request')));
  });

  it('permits only an admin to append a BMDC verification record', async () => {
    const entry = {
      doctorId: 'doctor-profile',
      outcome: 'found',
      verifiedByUid: 'admin',
      createdAt: new Date('2030-01-01T09:00:00Z'),
    };
    const adminDb = testEnv.authenticatedContext('admin').firestore();
    await assertSucceeds(setDoc(doc(adminDb, 'doctor_verification_history/admin-entry'), entry));

    const patientDb = testEnv.authenticatedContext('patient').firestore();
    await assertFails(setDoc(doc(patientDb, 'doctor_verification_history/patient-entry'), {
      ...entry,
      verifiedByUid: 'patient',
    }));
  });

  it('books an appointment that the AppointmentQueries patient query can read', async () => {
    const db = testEnv.authenticatedContext('patient').firestore();
    await assertSucceeds(setDoc(doc(db, 'appointments/booked-through-queries'), requestedAppointment()));
    // Mirrors AppointmentQueries.patientAppointments('patient') exactly.
    const snapshot = await getDocs(query(
      collection(db, 'appointments'),
      where('userId', '==', 'patient'),
      orderBy('createdAt', 'desc'),
    ));
    assert.equal(snapshot.docs.length, 1);
    assert.equal(snapshot.docs[0].data().status, 'requested');
  });
});
