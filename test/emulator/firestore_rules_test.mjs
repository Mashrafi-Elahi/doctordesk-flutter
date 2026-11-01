import { readFileSync } from 'node:fs';
import { after, afterEach, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, orderBy, query, setDoc, updateDoc, where } from 'firebase/firestore';

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
      setDoc(doc(db, 'doctors/doctor-profile'), {
        name: 'Dr One',
        claimedByUid: 'doctor',
        verificationStatus: 'unverified',
        isBmdcVerified: false,
      }),
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

  it('prevents a second active booking for the same patient, doctor, and date', async () => {
    const bookingKey = 'patient_doctor-profile_chamber-a_2030-01-01';
    const activeBooking = {
      userId: 'patient',
      doctorId: 'doctor-profile',
      chamberId: 'chamber-a',
      dateKey: '2030-01-01',
      appointmentId: 'appt-1',
      createdAt: new Date('2030-01-01T09:00:00Z'),
    };
    const patientDb = testEnv.authenticatedContext('patient').firestore();

    // First active booking creation succeeds
    await assertSucceeds(setDoc(doc(patientDb, `active_bookings/${bookingKey}`), activeBooking));

    // Second active booking with same key fails
    await assertFails(setDoc(doc(patientDb, `active_bookings/${bookingKey}`), {
      ...activeBooking,
      appointmentId: 'appt-2',
    }));
  });

  it('rejects non-admin updating doctor verification fields', async () => {
    const doctorDb = testEnv.authenticatedContext('doctor').firestore();
    // Non-admin can update general profile info (e.g. bio, name)
    await assertSucceeds(updateDoc(doc(doctorDb, 'doctors/doctor-profile'), {
      bio: 'Updated bio by doctor',
    }));
    // Non-admin cannot update verificationStatus
    await assertFails(updateDoc(doc(doctorDb, 'doctors/doctor-profile'), {
      verificationStatus: 'checked_found',
    }));
    // Non-admin cannot update isBmdcVerified
    await assertFails(updateDoc(doc(doctorDb, 'doctors/doctor-profile'), {
      isBmdcVerified: true,
    }));
  });

  it('allows admin to update doctor verification fields', async () => {
    const adminDb = testEnv.authenticatedContext('admin').firestore();
    await assertSucceeds(updateDoc(doc(adminDb, 'doctors/doctor-profile'), {
      verificationStatus: 'checked_found',
      isBmdcVerified: true,
      verifiedBy: 'admin',
    }));
  });

  it('rejects a review with spoofed userId', async () => {
    const patientDb = testEnv.authenticatedContext('patient').firestore();
    await assertFails(setDoc(doc(patientDb, 'reviews/spoofed-review'), {
      userId: 'stranger',
      doctorId: 'doctor-profile',
      rating: 5,
      comment: 'Spoofed',
      createdAt: new Date('2030-01-01T09:00:00Z'),
    }));
  });

  it('rejects a doctor reviewing their own doctorProfileId', async () => {
    const doctorDb = testEnv.authenticatedContext('doctor').firestore();
    await assertFails(setDoc(doc(doctorDb, 'reviews/doctor-self-review'), {
      userId: 'doctor',
      doctorId: 'doctor-profile',
      rating: 5,
      comment: 'Reviewing myself',
      createdAt: new Date('2030-01-01T09:00:00Z'),
    }));
  });

  it('allows a patient to review a doctor', async () => {
    const patientDb = testEnv.authenticatedContext('patient').firestore();
    await assertSucceeds(setDoc(doc(patientDb, 'reviews/patient-valid-review'), {
      userId: 'patient',
      doctorId: 'doctor-profile',
      rating: 5,
      comment: 'Great service!',
      createdAt: new Date('2030-01-01T09:00:00Z'),
    }));
  });

  it('prevents a patient from confirming an appointment, setting time, or setting queue number', async () => {
    const patientDb = testEnv.authenticatedContext('patient').firestore();

    // Patient cannot create appointment as confirmed
    await assertFails(setDoc(doc(patientDb, 'appointments/patient-direct-confirm'), requestedAppointment({
      status: 'confirmed',
    })));

    // Patient cannot create appointment with a queue position
    await assertFails(setDoc(doc(patientDb, 'appointments/patient-direct-queue'), requestedAppointment({
      queuePosition: 1,
    })));

    // Create a valid requested appointment
    await assertSucceeds(setDoc(doc(patientDb, 'appointments/patient-valid-appt'), requestedAppointment()));

    // Patient cannot update appointment status to confirmed
    await assertFails(updateDoc(doc(patientDb, 'appointments/patient-valid-appt'), {
      status: 'confirmed',
    }));

    // Patient cannot update scheduledTime
    await assertFails(updateDoc(doc(patientDb, 'appointments/patient-valid-appt'), {
      scheduledTime: new Date('2030-01-02T10:00:00Z'),
    }));
  });

  it('prevents a patient from writing to queues collection', async () => {
    const patientDb = testEnv.authenticatedContext('patient').firestore();
    await assertFails(setDoc(doc(patientDb, 'queues/chamber-a_2030-01-01'), {
      chamberId: 'chamber-a',
      date: '2030-01-01',
      currentNumber: 1,
    }));
  });

  it('prevents a patient from creating or activating a chat', async () => {
    const patientDb = testEnv.authenticatedContext('patient').firestore();
    // Patient cannot create chat
    await assertFails(setDoc(doc(patientDb, 'chats/patient-created-chat'), {
      patientUid: 'patient',
      doctorUid: 'doctor',
      isActive: true,
      createdAt: new Date('2030-01-01T09:00:00Z'),
    }));

    // Seed inactive chat by doctor
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'chats/care-chat'), {
        patientUid: 'patient',
        doctorUid: 'doctor',
        isActive: false,
        messageCount: 0,
      });
    });

    // Patient cannot activate chat
    await assertFails(updateDoc(doc(patientDb, 'chats/care-chat'), {
      isActive: true,
    }));
  });

  it('prevents a stranger from reading a chat', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'chats/private-chat'), {
        patientUid: 'patient',
        doctorUid: 'doctor',
        participants: ['patient', 'doctor'],
      });
    });

    const strangerDb = testEnv.authenticatedContext('stranger').firestore();
    await assertFails(getDoc(doc(strangerDb, 'chats/private-chat')));

    const patientDb = testEnv.authenticatedContext('patient').firestore();
    await assertSucceeds(getDoc(doc(patientDb, 'chats/private-chat')));
  });

  it('prevents a doctor from setting isAdmin on their own user profile', async () => {
    const doctorDb = testEnv.authenticatedContext('doctor').firestore();
    await assertFails(updateDoc(doc(doctorDb, 'users/doctor'), {
      'roles.isAdmin': true,
    }));
    await assertFails(updateDoc(doc(doctorDb, 'users/doctor'), {
      roles: { isDoctor: true, isAdmin: true },
    }));
  });
});
