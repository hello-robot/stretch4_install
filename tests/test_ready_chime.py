#!/usr/bin/env python3
"""
Unit tests for the readiness decision in hello-ready-chime and for ready.wav.
No robot, no server, no zmq: the decision is fed fake status samples shaped like
the ones stretch_body_server publishes.

    python3 tests/test_ready_chime.py
"""
import copy
import hashlib
import importlib.machinery
import importlib.util
import math
import os
import struct
import subprocess
import sys
import tempfile
import unittest
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
SOUNDS = os.path.join(HERE, '..', 'factory', '24.04', 'sounds')
PLAYER = os.path.join(SOUNDS, 'hello-ready-chime')
WAV = os.path.join(SOUNDS, 'ready.wav')
GENERATOR = os.path.join(SOUNDS, 'make_ready_chime.py')


def load_player():
    loader = importlib.machinery.SourceFileLoader('hello_ready_chime', PLAYER)
    spec = importlib.util.spec_from_loader('hello_ready_chime', loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


rc = load_player()


def transport(errors=0):
    return {'rpc_duration_us': 300.0,
            'async': {'read_error': 0, 'write_error': 0, 'transactions': 0},
            'sync': {'read_error': errors, 'write_error': 0, 'transactions': 1}}


def stepper(errors=0, drv_fault=False):
    return {'motor': {'transport': transport(errors), 'is_drv_fault': drv_fault, 'pos': 0.0}}


def sample(status_id=100, server_state='RUNNING', power_state='STATE_ACTIVE', runstop=False):
    pp = {'transport': transport(), 'adapter_fault': False, 'runstop_event': runstop,
          'voltage': 25.8, 'state': 4160,
          'power_diagnostics': {'power_state_name': power_state, 'power_state': 0, '_valid': True},
          'power_diagnostics_meta': {'available': True, 'transport_error': None},
          'status_aux': {'current_pwr_state_name': power_state}}
    wheels = {'wheel_%d' % i: {'transport': transport(), 'is_drv_fault': False} for i in range(3)}
    omnibase = dict(wheels, x=0.0, y=0.0, theta=0.0)
    joint = {'hardware_error': 0, 'comm_errors': {'n_rx': 0, 'n_tx': 0, 'n_gsr': 0}, 'pos': 0.0}
    return {
        'server': {'state': server_state, 'status_id': status_id, 'control_loop': {}},
        'routines': {'active_routine': 'routine_nop'},
        'safety_layer': {},
        'arm': stepper(), 'lift': stepper(),
        'omnibase': omnibase, 'base': omnibase,
        'power_periph': pp, 'pimu': pp,
        'end_of_arm': {'loop': {'state': 'RUNNING'},
                       'joint_names': ['wrist_yaw', 'wrist_pitch'],
                       'wrist_yaw': copy.deepcopy(joint), 'wrist_pitch': copy.deepcopy(joint)},
    }


class JudgeTests(unittest.TestCase):
    def test_ready_sample_has_no_reasons(self):
        self.assertEqual(rc.judge(sample()), [])
        self.assertEqual(rc.judge(sample(101), sample(100)), [])

    def test_power_board_not_active(self):
        for state in ('STATE_SLEEP', 'STATE_SHUTDOWN', 'UNKNOWN_7'):
            reasons = rc.judge(sample(power_state=state))
            self.assertEqual(reasons, ['power board %s' % state])

    def test_power_state_falls_back_to_status_aux(self):
        s = sample()
        del s['power_periph']['power_diagnostics']
        self.assertEqual(rc.judge(s), [])
        s['power_periph']['status_aux']['current_pwr_state_name'] = 'STATE_SLEEP_CHRG'
        self.assertEqual(rc.judge(s), ['power board STATE_SLEEP_CHRG'])
        del s['power_periph']['status_aux']
        self.assertEqual(rc.judge(s), ['power board state unknown'])

    def test_server_not_running_or_stalled(self):
        self.assertEqual(rc.judge(sample(server_state='INVALID')), ['server state INVALID'])
        self.assertEqual(rc.judge(sample(server_state='PAUSED')), ['server state PAUSED'])
        self.assertEqual(rc.judge(sample(100), sample(100)), ['status not advancing'])
        self.assertEqual(rc.judge({}), ['no status'])
        self.assertEqual(rc.judge(None), ['no status'])

    def test_subsystem_not_reporting(self):
        s = sample()
        s['lift'] = {}
        self.assertEqual(rc.judge(s), ['lift not reporting'])
        s = sample()
        del s['power_periph']
        del s['pimu']
        self.assertEqual(rc.judge(s), ['no power board in status'])

    def test_subsystem_faults(self):
        s = sample()
        s['arm']['motor']['is_drv_fault'] = True
        self.assertEqual(rc.judge(s), ['arm.motor driver fault'])

        prev, s = sample(100), sample(101)
        s['omnibase']['wheel_1']['transport']['sync']['read_error'] = 1
        self.assertEqual(rc.judge(s, prev), ['omnibase.wheel_1 transport errors rising'])
        # a steady old count is not a fault
        prev['omnibase']['wheel_1']['transport']['sync']['read_error'] = 1
        self.assertEqual(rc.judge(s, prev), [])

        prev, s = sample(100), sample(101)
        s['power_periph']['transport']['async']['write_error'] = 2
        self.assertEqual(rc.judge(s, prev), ['power_periph transport errors rising'])

        s = sample()
        s['power_periph']['adapter_fault'] = True
        self.assertEqual(rc.judge(s), ['adapter fault'])

        s = sample()
        s['power_periph']['power_diagnostics_meta']['transport_error'] = 'timeout'
        self.assertEqual(rc.judge(s), ['power diagnostics transport error: timeout'])

        s = sample()
        s['end_of_arm']['wrist_pitch']['hardware_error'] = 32
        self.assertEqual(rc.judge(s), ['end_of_arm.wrist_pitch hardware error 32'])

        prev, s = sample(100), sample(101)
        s['end_of_arm']['wrist_yaw']['comm_errors']['n_rx'] = 3
        self.assertEqual(rc.judge(s, prev), ['end_of_arm.wrist_yaw comm errors rising'])

        s = sample()
        s['end_of_arm']['loop']['state'] = 'PAUSED'
        self.assertEqual(rc.judge(s), ['end_of_arm loop PAUSED'])

    def test_runstop_is_a_note_not_a_fault(self):
        s = sample(runstop=True)
        self.assertEqual(rc.judge(s), [])
        self.assertEqual(rc.notes(s), ['runstop pressed'])
        self.assertEqual(rc.notes(sample()), [])


class Clock:
    def __init__(self):
        self.t = 1000.0

    def now(self):
        return self.t

    def sleep(self, s):
        self.t += s


def run_wait(samples, cap_s=90.0, hold_s=2.0, poll_s=0.1, exists=True):
    """Drive wait_until_ready with a fake clock. samples(i, t) returns the i-th status;
    each read advances the clock by poll_s like a real poll would."""
    clock = Clock()
    count = {'n': 0}

    def read(timeout_s):
        clock.t += timeout_s
        i = count['n']
        count['n'] += 1
        return samples(i, clock.t)

    return rc.wait_until_ready(read, cap_s=cap_s, hold_s=hold_s, poll_s=poll_s,
                               now=clock.now, sleep=clock.sleep, exists=lambda p: exists)


class WaitTests(unittest.TestCase):
    def test_ready_after_the_hold(self):
        ready, reason, elapsed = run_wait(lambda i, t: sample(100 + i))
        self.assertTrue(ready)
        self.assertEqual(reason, 'ready')
        self.assertGreaterEqual(elapsed, 2.0)
        self.assertLess(elapsed, 3.0)

    def test_ready_notes_the_runstop(self):
        ready, reason, _ = run_wait(lambda i, t: sample(100 + i, runstop=True))
        self.assertTrue(ready)
        self.assertEqual(reason, 'ready (runstop pressed)')

    def test_fault_inside_the_hold_restarts_it(self):
        def samples(i, t):
            s = sample(100 + i)
            if i == 5:
                s['lift']['motor']['is_drv_fault'] = True
            return s
        ready, reason, elapsed = run_wait(samples)
        self.assertTrue(ready)
        # each poll is 0.2 s of fake time; the hold restarts after the fault at 1.1 s
        self.assertGreaterEqual(elapsed, 5 * 0.2 + 2.0)
        self.assertLess(elapsed, 4.0)

    def test_timeout_when_power_board_never_active(self):
        ready, reason, elapsed = run_wait(lambda i, t: sample(100 + i, power_state='STATE_SLEEP'), cap_s=10.0)
        self.assertFalse(ready)
        self.assertEqual(reason, 'power board STATE_SLEEP')
        self.assertGreaterEqual(elapsed, 10.0)

    def test_timeout_when_status_stalls(self):
        ready, reason, _ = run_wait(lambda i, t: sample(100), cap_s=5.0)
        self.assertFalse(ready)
        self.assertEqual(reason, 'status not advancing')

    def test_timeout_without_a_server(self):
        ready, reason, _ = run_wait(lambda i, t: None, cap_s=5.0)
        self.assertFalse(ready)
        self.assertEqual(reason, 'no status from stretch_body_server')
        ready, reason, _ = run_wait(lambda i, t: sample(100 + i), cap_s=5.0, exists=False)
        self.assertFalse(ready)
        self.assertIn('status socket', reason)


class WavTests(unittest.TestCase):
    def test_file_shape(self):
        with wave.open(WAV) as w:
            self.assertEqual(w.getnchannels(), 1)
            self.assertEqual(w.getframerate(), 22050)
            self.assertEqual(w.getsampwidth(), 2)
            n = w.getnframes()
            pcm = struct.unpack('<%dh' % n, w.readframes(n))
        self.assertTrue(1.0 <= n / 22050.0 <= 1.4)
        self.assertEqual(pcm[0], 0)
        self.assertEqual(pcm[-1], 0)
        peak_dbfs = 20 * math.log10(max(abs(v) for v in pcm) / 32767.0)
        self.assertTrue(-12.5 <= peak_dbfs <= -11.5, peak_dbfs)
        # soft edges: nothing near the peak in the first and last 10 ms
        edge = 220
        self.assertLess(max(abs(v) for v in pcm[:edge]), 0.35 * 8231)
        self.assertLess(max(abs(v) for v in pcm[-edge:]), 0.35 * 8231)
        self.assertLess(os.path.getsize(WAV), 80 * 1024)

    def test_generator_reproduces_the_committed_file(self):
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, 'ready.wav')
            subprocess.run([sys.executable, GENERATOR, out], check=True, capture_output=True)
            with open(out, 'rb') as f, open(WAV, 'rb') as g:
                self.assertEqual(hashlib.sha256(f.read()).hexdigest(),
                                 hashlib.sha256(g.read()).hexdigest())


class PlayerCliTests(unittest.TestCase):
    def test_help_and_defaults(self):
        p = rc.build_parser()
        a = p.parse_args([])
        self.assertEqual(a.timeout, 90.0)
        self.assertEqual(a.hold, 2.0)
        self.assertFalse(a.test)
        self.assertTrue(p.parse_args(['--test']).test)

    def test_wait_fails_fast_without_a_socket(self):
        with tempfile.TemporaryDirectory() as d:
            res = subprocess.run([sys.executable, PLAYER, '--check', '--timeout', '0.3',
                                  '--socket', os.path.join(d, 'none')],
                                 capture_output=True, text=True)
        self.assertEqual(res.returncode, 1)
        self.assertIn('no chime', res.stdout)
        self.assertIn('status socket', res.stdout)


if __name__ == '__main__':
    unittest.main()
