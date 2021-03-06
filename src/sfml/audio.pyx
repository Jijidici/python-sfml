#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# pySFML - Python bindings for SFML
# Copyright 2012-2013, Jonathan De Wachter <dewachter.jonathan@gmail.com>
#
# This software is released under the LGPLv3 license.
# You should have received a copy of the GNU Lesser General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

#from libc.stdlib cimport malloc, free
#from cython.operator cimport preincrement as preinc, dereference as deref

cimport cython
from libc.stdlib cimport malloc, free
from libc.string cimport memcpy

cimport libcpp.sfml as sf
from libcpp.sfml cimport Int8, Int16, Int32, Int64
from libcpp.sfml cimport Uint8, Uint16, Uint32, Uint64
from libcpp.sfml cimport Vector3f


cdef extern from "pysfml/system_api.h":
	object popLastErrorMessage()
	int import_sfml__system()
import_sfml__system()

cdef extern from "DerivableSoundStream.hpp":
	cdef cppclass DerivableSoundStream:
		DerivableSoundStream(void*)
		void initialize(unsigned int, unsigned int)

cdef extern from "DerivableSoundRecorder.hpp":
	cdef cppclass DerivableSoundRecorder:
		DerivableSoundRecorder(void*)

from pysfml.system cimport Vector3, Time
from pysfml.system cimport to_vector3

cdef Time wrap_time(sf.Time* p):
	cdef Time r = Time.__new__(Time)
	r.p_this = p
	return r


cdef class Listener:
	def __init__(self):
		NotImplementedError("This class is not meant to be instanciated!")

	@classmethod
	def get_global_volume(cls):
		return sf.listener.getGlobalVolume()

	@classmethod
	def set_global_volume(cls, float volume):
		sf.listener.setGlobalVolume(volume)

	@classmethod
	def get_position(cls):
		cdef Vector3f v = sf.listener.getPosition()
		return to_vector3(&v)

	@classmethod
	def set_position(cls, position):
		x, y, z = position
		sf.listener.setPosition(x, y, z)

	@classmethod
	def get_direction(cls):
		cdef Vector3f v = sf.listener.getDirection()
		return to_vector3(&v)

	@classmethod
	def set_direction(cls, direction):
		x, y, z = direction
		sf.listener.setDirection(x, y, z)

cdef class Chunk:
	cdef Int16* m_samples
	cdef size_t m_sampleCount
	cdef bint   delete_this

	def __cinit__(self):
		self.m_samples = NULL
		self.m_sampleCount = 0
		self.delete_this = False

	def __dealloc__(self):
		if self.delete_this:
			free(self.m_samples)

	def __len__(self):
		return self.m_sampleCount

	def __getitem__(self, size_t key):
		return self.m_samples[key]

	def __setitem__(self, size_t key, Int16 other):
		self.m_samples[key] = other

	property data:
		def __get__(self):
			return (<char*>self.m_samples)[:len(self)*2]

		def __set__(self, bdata):
			cdef char* data = <bytes>bdata

			if len(bdata) % 2:
				raise ValueError("Chunk data lenght must be even as it represents a 16bit array")

			if self.delete_this:
				free(self.m_samples)
				self.m_sampleCount = 0

			self.m_samples = <Int16*>malloc(len(bdata))
			memcpy(self.m_samples, data, len(bdata))
			self.m_sampleCount = len(bdata) // 2

			self.delete_this = True

cdef api object create_chunk():
	cdef Chunk r = Chunk.__new__(Chunk)
	r.m_samples = NULL
	r.m_sampleCount = 0
	r.delete_this = False
	return r

cdef api Int16* terminate_chunk(chunk):
	cdef Chunk p = <Chunk>chunk
	p.delete_this = False
	return p.m_samples

cdef api object wrap_chunk(Int16* samples, unsigned int sample_count, bint delete):
	cdef Chunk r = Chunk.__new__(Chunk)
	r.m_samples = samples
	r.m_sampleCount = sample_count
	r.delete_this = delete
	return r

cdef class SoundBuffer:
	cdef sf.SoundBuffer *p_this
	cdef bint                delete_this

	def __init__(self):
		raise UserWarning("Use specific methods")

	def __dealloc__(self):
		if self.delete_this: del self.p_this

	def __repr__(self): pass
	def __str__(self): pass

	@classmethod
	def from_file(cls, filename):
		cdef sf.SoundBuffer *p = new sf.SoundBuffer()
		cdef char* encoded_filename

		encoded_filename_temporary = filename.encode('UTF-8')
		encoded_filename = encoded_filename_temporary

		if p.loadFromFile(encoded_filename): return wrap_soundbuffer(p)

		del p
		raise IOError(popLastErrorMessage())

	@classmethod
	def from_memory(cls, bytes data):
		cdef sf.SoundBuffer *p = new sf.SoundBuffer()

		if p.loadFromMemory(<char*>data, len(data)): return wrap_soundbuffer(p)

		del p
		raise IOError(popLastErrorMessage())

	@classmethod
	def from_samples(cls, Chunk samples, unsigned int channel_count, unsigned int sample_rate):
		cdef sf.SoundBuffer *p = new sf.SoundBuffer()

		if p.loadFromSamples(samples.m_samples, samples.m_sampleCount, channel_count, sample_rate):
			return wrap_soundbuffer(p)

		del p
		raise IOError(popLastErrorMessage())

	def to_file(self, filename):
		cdef char* encoded_filename

		encoded_filename_temporary = filename.encode('UTF-8')
		encoded_filename = encoded_filename_temporary

		self.p_this.saveToFile(encoded_filename)

	property samples:
		def __get__(self):
			cdef Chunk r = Chunk.__new__(Chunk)
			r.m_samples = <Int16*>self.p_this.getSamples()
			r.m_sampleCount = self.p_this.getSampleCount()
			return r

	property sample_rate:
		def __get__(self):
			return self.p_this.getSampleRate()

	property channel_count:
		def __get__(self):
			return self.p_this.getChannelCount()

	property duration:
		def __get__(self):
			cdef sf.Time* p = new sf.Time()
			p[0] = self.p_this.getDuration()
			return wrap_time(p)

cdef SoundBuffer wrap_soundbuffer(sf.SoundBuffer *p, bint delete_this=True):
	cdef SoundBuffer r = SoundBuffer.__new__(SoundBuffer)
	r.p_this = p
	r.delete_this = delete_this
	return r


cdef class SoundSource:
	STOPPED = sf.soundsource.Stopped
	PAUSED = sf.soundsource.Paused
	PLAYING = sf.soundsource.Playing

	cdef sf.SoundSource *p_soundsource

	def __init__(self, *args, **kwargs):
		raise UserWarning("This class is not meant to be used directly")

	property pitch:
		def __get__(self):
			return self.p_soundsource.getPitch()

		def __set__(self, float pitch):
			self.p_soundsource.setPitch(pitch)

	property volume:
		def __get__(self):
			return self.p_soundsource.getVolume()

		def __set__(self, float volume):
			self.p_soundsource.setVolume(volume)

	property position:
		def __get__(self):
			cdef Vector3f v = self.p_soundsource.getPosition()
			return to_vector3(&v)

		def __set__(self, position):
			x, y, z = position
			self.p_soundsource.setPosition(x, y, z)

	property relative_to_listener:
		def __get__(self):
			return self.p_soundsource.isRelativeToListener()

		def __set__(self, bint relative):
			self.p_soundsource.setRelativeToListener(relative)

	property min_distance:
		def __get__(self):
			return self.p_soundsource.getMinDistance()

		def __set__(self, float distance):
			self.p_soundsource.setMinDistance(distance)

	property attenuation:
		def __get__(self):
			return self.p_soundsource.getAttenuation()

		def __set__(self, float attenuation):
			self.p_soundsource.setAttenuation(attenuation)


cdef class Sound(SoundSource):
	cdef sf.Sound *p_this
	cdef SoundBuffer   m_buffer

	def __init__(self, SoundBuffer buffer=None):
		self.p_this = new sf.Sound()
		self.p_soundsource = <sf.SoundSource*>self.p_this

		if buffer: self.buffer = buffer

	def __dealloc__(self):
		del self.p_this

	def __repr__(self):
		return "sf.Sound()"

	def play(self):
		self.p_this.play()

	def pause(self):
		self.p_this.pause()

	def stop(self):
		self.p_this.stop()

	property buffer:
		def __get__(self):
			return self.m_buffer

		def __set__(self, SoundBuffer buffer):
			self.p_this.setBuffer(buffer.p_this[0])
			self.m_buffer = buffer

	property loop:
		def __get__(self):
			return self.p_this.getLoop()

		def __set__(self, bint loop):
			self.p_this.setLoop(loop)

	property playing_offset:
		def __get__(self):
			cdef sf.Time* p = new sf.Time()
			p[0] = self.p_this.getPlayingOffset()
			return wrap_time(p)

		def __set__(self, Time time_offset):
			self.p_this.setPlayingOffset(time_offset.p_this[0])

	property status:
		def __get__(self):
			return self.p_this.getStatus()


cdef class SoundStream(SoundSource):
	cdef sf.SoundStream *p_soundstream

	def __init__(self):
		if self.__class__ == SoundStream:
			raise NotImplementedError("SoundStream is abstract")

		elif self.__class__ not in [Music]:
			self.p_soundstream = <sf.SoundStream*> new DerivableSoundStream(<void*>self)
			self.p_soundsource = <sf.SoundSource*>self.p_soundstream

	def play(self):
		self.p_soundstream.play()

	def pause(self):
		self.p_soundstream.pause()

	def stop(self):
		self.p_soundstream.stop()

	property channel_count:
		def __get__(self):
			return self.p_soundstream.getChannelCount()

	property sample_rate:
		def __get__(self):
			return self.p_soundstream.getSampleRate()

	property status:
		def __get__(self):
			return self.p_soundstream.getStatus()

	property playing_offset:
		def __get__(self):
			cdef sf.Time* p = new sf.Time()
			p[0] = self.p_soundstream.getPlayingOffset()
			return wrap_time(p)

		def __set__(self, Time time_offset):
			self.p_soundstream.setPlayingOffset(time_offset.p_this[0])

	property loop:
		def __get__(self):
			return self.p_soundstream.getLoop()

		def __set__(self, bint loop):
			self.p_soundstream.setLoop(loop)

	def initialize(self, unsigned int channel_count, unsigned int sample_rate):
		if self.__class__ not in [Music]:
			(<DerivableSoundStream*>self.p_soundstream).initialize(channel_count, sample_rate)

	def on_get_data(self, data): pass
	def on_seek(self, time_offset): pass

cdef class Music(SoundStream):
	cdef sf.Music *p_this

	def __init__(self):
		raise UserWarning("Use specific constructor")

	def __dealloc__(self):
		del self.p_this

	@classmethod
	def from_file(cls, filename):
		cdef sf.Music *p = new sf.Music()
		cdef char* encoded_filename

		encoded_filename_temporary = filename.encode('UTF-8')
		encoded_filename = encoded_filename_temporary

		if p.openFromFile(encoded_filename): return wrap_music(p)

		del p
		raise IOError(popLastErrorMessage())

	@classmethod
	def from_memory(cls, bytes data):
		cdef sf.Music *p = new sf.Music()

		if p.openFromMemory(<char*>data, len(data)): return wrap_music(p)

		del p
		raise IOError(popLastErrorMessage())

	property duration:
		def __get__(self):
			cdef sf.Time* p = new sf.Time()
			p[0] = self.p_this.getDuration()
			return wrap_time(p)


cdef Music wrap_music(sf.Music *p):
	cdef Music r = Music.__new__(Music)
	r.p_this = p
	r.p_soundstream = <sf.SoundStream*>p
	r.p_soundsource = <sf.SoundSource*>p
	return r


cdef class SoundRecorder:
	cdef sf.SoundRecorder *p_soundrecorder

	def __init__(self):
		if self.__class__ == SoundRecorder:
			raise NotImplementedError("SoundRecorder is abstract")

		elif self.__class__ is not SoundBufferRecorder:
			self.p_soundrecorder = <sf.SoundRecorder*>new DerivableSoundRecorder(<void*>self)

	def __dealloc__(self):
		if self.__class__ is SoundRecorder:
			del self.p_soundrecorder

	def start(self, unsigned int sample_rate=44100):
		self.p_soundrecorder.start(sample_rate)

	def stop(self):
		with nogil: self.p_soundrecorder.stop()

	property sample_rate:
		def __get__(self):
			return self.p_soundrecorder.getSampleRate()

	@classmethod
	def is_available(cls):
		return sf.soundrecorder.isAvailable()

	def on_start(self):
		return True

	def on_process_samples(self, chunk):
		return True

	def on_stop(self):
		pass

cdef class SoundBufferRecorder(SoundRecorder):
	cdef sf.SoundBufferRecorder *p_this
	cdef SoundBuffer                 m_buffer

	def __init__(self):
		self.p_this = new sf.SoundBufferRecorder()
		self.p_soundrecorder = <sf.SoundRecorder*>self.p_this

		self.m_buffer = wrap_soundbuffer(<sf.SoundBuffer*>&self.p_this.getBuffer(), False)

	def __dealloc__(self):
		del self.p_this

	property buffer:
		def __get__(self):
			return self.m_buffer
