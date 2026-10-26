use std::fs::File;
use std::io::BufReader;
use std::sync::{Arc, Mutex};
use rand::seq::SliceRandom;
use rand::thread_rng;
use rodio::{Decoder, OutputStream, OutputStreamHandle, Sink};
use crate::models::{RepeatMode, Track};

pub struct AudioPlayer {
    _stream: Option<OutputStream>,
    _stream_handle: Option<OutputStreamHandle>,
    sink: Option<Sink>,
    pub original_queue: Vec<Track>,
    pub playback_queue: Vec<Track>,
    pub current_index: usize,
    pub is_playing: bool,
    pub is_shuffled: bool,
    pub repeat_mode: RepeatMode,
    pub volume: f32,
    pub elapsed_seconds: f32,
}

impl AudioPlayer {
    pub fn new() -> Arc<Mutex<Self>> {
        let (stream, stream_handle) = match std::panic::catch_unwind(|| OutputStream::try_default()) {
            Ok(Ok((s, h))) => (Some(s), Some(h)),
            _ => (None, None),
        };

        let sink = stream_handle.as_ref().and_then(|h| {
            std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| Sink::try_new(h).ok()))
                .ok()
                .flatten()
        });

        Arc::new(Mutex::new(Self {
            _stream: stream,
            _stream_handle: stream_handle,
            sink,
            original_queue: Vec::new(),
            playback_queue: Vec::new(),
            current_index: 0,
            is_playing: false,
            is_shuffled: false,
            repeat_mode: RepeatMode::Off,
            volume: 0.8,
            elapsed_seconds: 0.0,
        }))
    }

    pub fn ensure_sink(&mut self) -> bool {
        if self.sink.is_some() {
            return true;
        }
        if self._stream_handle.is_none() {
            if let Ok(Ok((s, h))) = std::panic::catch_unwind(|| OutputStream::try_default()) {
                self._stream = Some(s);
                self._stream_handle = Some(h);
            }
        }
        if let Some(ref h) = self._stream_handle {
            if let Ok(Ok(sink)) = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| Sink::try_new(h))) {
                self.sink = Some(sink);
                return true;
            }
        }
        false
    }

    pub fn current_track(&self) -> Option<&Track> {
        self.playback_queue.get(self.current_index)
    }

    pub fn load_playlist(&mut self, tracks: Vec<Track>, start_index: usize) {
        if tracks.is_empty() {
            return;
        }
        self.original_queue = tracks.clone();
        self.playback_queue = tracks;
        self.current_index = start_index.min(self.playback_queue.len() - 1);

        if self.is_shuffled {
            self.apply_shuffle_keeping_current();
        }

        self.play_current();
    }

    pub fn play_current(&mut self) {
        self.ensure_sink();
        self.elapsed_seconds = 0.0;
        self.is_playing = true;
        if let Some(track) = self.playback_queue.get(self.current_index) {
            if let Ok(file) = File::open(&track.file_path) {
                let reader = BufReader::new(file);
                if let Ok(source) = Decoder::new(reader) {
                    if let Some(ref sink) = self.sink {
                        sink.stop();
                        sink.set_volume(self.volume);
                        sink.append(source);
                        sink.play();
                    }
                }
            }
        }
    }

    pub fn toggle_play_pause(&mut self) {
        self.ensure_sink();
        if let Some(ref sink) = self.sink {
            if sink.is_paused() {
                sink.play();
                self.is_playing = true;
            } else if !sink.empty() {
                sink.pause();
                self.is_playing = false;
            } else {
                // If stopped/empty, replay current
                self.play_current();
            }
        } else {
            self.is_playing = !self.is_playing;
        }
    }

    pub fn toggle_shuffle(&mut self) {
        self.is_shuffled = !self.is_shuffled;
        if self.playback_queue.is_empty() {
            return;
        }

        if self.is_shuffled {
            self.apply_shuffle_keeping_current();
        } else {
            // Restore original sequence without jumping current track
            if let Some(current) = self.playback_queue.get(self.current_index).cloned() {
                self.playback_queue = self.original_queue.clone();
                if let Some(pos) = self.playback_queue.iter().position(|t| t.id == current.id) {
                    self.current_index = pos;
                }
            }
        }
    }

    fn apply_shuffle_keeping_current(&mut self) {
        if self.playback_queue.is_empty() {
            return;
        }
        let current_track = self.playback_queue[self.current_index].clone();
        let mut others: Vec<Track> = self.original_queue
            .iter()
            .filter(|t| t.id != current_track.id)
            .cloned()
            .collect();

        let mut rng = thread_rng();
        others.shuffle(&mut rng);

        self.playback_queue = vec![current_track];
        self.playback_queue.extend(others);
        self.current_index = 0;
    }

    pub fn cycle_repeat_mode(&mut self) {
        self.repeat_mode = match self.repeat_mode {
            RepeatMode::Off => RepeatMode::All,
            RepeatMode::All => RepeatMode::One,
            RepeatMode::One => RepeatMode::Off,
        };
    }

    pub fn next(&mut self) {
        if self.playback_queue.is_empty() {
            return;
        }

        if self.current_index + 1 < self.playback_queue.len() {
            self.current_index += 1;
            self.play_current();
        } else if self.repeat_mode == RepeatMode::All {
            self.current_index = 0;
            self.play_current();
        } else {
            self.is_playing = false;
        }
    }

    pub fn previous(&mut self) {
        if self.playback_queue.is_empty() {
            return;
        }

        if self.elapsed_seconds > 3.0 {
            // If already 3 seconds in, restart song
            self.play_current();
        } else if self.current_index > 0 {
            self.current_index -= 1;
            self.play_current();
        } else {
            self.play_current();
        }
    }

    pub fn set_volume(&mut self, val: f32) {
        self.volume = val.clamp(0.0, 1.0);
        if let Some(ref sink) = self.sink {
            sink.set_volume(self.volume);
        }
    }

    pub fn tick(&mut self, dt: f32) {
        if self.is_playing {
            self.elapsed_seconds += dt;
            if let Some(ref sink) = self.sink {
                if sink.empty() && self.elapsed_seconds > 1.0 {
                    // Track ended
                    if self.repeat_mode == RepeatMode::One {
                        self.play_current();
                    } else {
                        self.next();
                    }
                }
            } else if let Some(track) = self.current_track() {
                if self.elapsed_seconds >= track.duration_secs as f32 {
                    if self.repeat_mode == RepeatMode::One {
                        self.play_current();
                    } else {
                        self.next();
                    }
                }
            }
        }
    }
}
