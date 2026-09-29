#include "OFS_Waveform.h"
#include "OFS_Util.h"
#include "OFS_Profiling.h"
#include "OFS_GL.h"
#include "OFS_ScriptTimeline.h"

#define DR_FLAC_IMPLEMENTATION
#include "dr_flac.h"

#include "subprocess.h"

#include <array>
#include <filesystem>

bool OFS_Waveform::LoadFlac(const std::string& output) noexcept
{
	drflac* flac = drflac_open_file(output.c_str(), NULL);
	if (!flac) return false;

	std::vector<drflac_int16> ChunkSamples; ChunkSamples.resize(48000);
	constexpr int SamplesPerLine = 300; 

	float minSample = 0.f;
	float maxSample = 0.f;

	uint32_t sampleCount = 0;
	float avgSample = 0.f;
	Clear();
	samples.reserve(flac->totalPCMFrameCount / SamplesPerLine);
	while ((sampleCount = drflac_read_pcm_frames_s16(flac, ChunkSamples.size(), ChunkSamples.data())) > 0) {
		for (int sampleIdx = 0; sampleIdx < sampleCount; sampleIdx += SamplesPerLine) {
			int samplesInThisLine = std::min(SamplesPerLine, (int)sampleCount - sampleIdx);
			for (int i = 0; i < samplesInThisLine; i += 1) {
				drflac_int16 sample = ChunkSamples[sampleIdx + i];
				sample = std::abs(sample);
				auto floatSample = sample / 32768.f;
				avgSample += floatSample;
			}
			avgSample /= (float)SamplesPerLine;
			minSample = Util::Min(minSample, avgSample);
			maxSample = Util::Max(maxSample, avgSample);
			samples.emplace_back(avgSample);
			avgSample = 0.f;
		}
	}
	drflac_close(flac);
	samples.shrink_to_fit();
	if (samples.empty()) return false;

	if(std::abs(minSample) > std::abs(maxSample)) {
		maxSample = std::abs(minSample);
	}
	else {
		minSample = -maxSample;
	}

	for(auto& sample : samples) {
		sample = Util::MapRange(sample, minSample, maxSample, -1.f, 1.f);
	}

	return true;
}

bool OFS_Waveform::GenerateAndLoadFlac(const std::string& ffmpegPath, const std::string& videoPath, const std::string& output) noexcept
{
	generating = true;
	auto outputFile = Util::PathFromString(output);
	auto removeOutput = [&]() noexcept {
		std::error_code ec;
		std::filesystem::remove(outputFile, ec);
	};
	auto fail = [&]() noexcept {
		removeOutput();
		generating = false;
		return false;
	};

	if (ffmpegPath.empty()) {
		LOG_ERROR("Could not find ffmpeg. Install ffmpeg or add it to PATH, then update the waveform.");
		return fail();
	}
	if (videoPath.empty()) {
		LOG_ERROR("Could not generate waveform: no video is loaded.");
		return fail();
	}
	std::error_code removeError;
	std::filesystem::remove(outputFile, removeError);
	if (removeError) {
		LOGF_ERROR("Could not remove old waveform audio '%s': %s", output.c_str(), removeError.message().c_str());
		return fail();
	}

	std::array<const char*, 14> args =
	{
		ffmpegPath.c_str(),
		"-y",
		"-hide_banner",
		"-nostdin",
		"-nostats",
		"-loglevel",
		"error",
		"-i", videoPath.c_str(),
		"-vn",
		"-ac", "1",
		output.c_str(),
		nullptr
	};
	constexpr size_t MaxStderrBytes = 2048;
	std::array<char, MaxStderrBytes> stderrBuffer{};
	size_t stderrSize = 0;
	size_t stderrNext = 0;
	bool stderrTruncated = false;
	struct subprocess_s proc;
	if(subprocess_create(args.data(), subprocess_option_no_window | subprocess_option_enable_async, &proc) != 0) {
		LOGF_ERROR("Could not start ffmpeg at '%s' while generating the waveform.", ffmpegPath.c_str());
		return fail();
	}

	if (proc.stdin_file) {
		fclose(proc.stdin_file);
		proc.stdin_file = nullptr;
	}
	if(proc.stdout_file) 
	{
		fclose(proc.stdout_file);
		proc.stdout_file = nullptr;
	}

	char stderrChunk[512];
	unsigned bytesRead = 0;
	while ((bytesRead = subprocess_read_stderr(&proc, stderrChunk, sizeof(stderrChunk))) > 0) {
		for (unsigned i = 0; i < bytesRead; ++i) {
			stderrBuffer[stderrNext] = stderrChunk[i];
			stderrNext = (stderrNext + 1) % stderrBuffer.size();
			if (stderrSize < stderrBuffer.size()) ++stderrSize;
			else stderrTruncated = true;
		}
	}
	auto getStderrDiagnostic = [&]() {
		std::string diagnostic;
		diagnostic.reserve(stderrSize + 40);
		const size_t start = stderrTruncated ? stderrNext : 0;
		for (size_t i = 0; i < stderrSize; ++i) {
			const char ch = stderrBuffer[(start + i) % stderrBuffer.size()];
			diagnostic += (ch == '\0') ? ' ' : ch;
		}
		if (stderrTruncated) {
			const size_t firstLineEnd = diagnostic.find('\n');
			if (firstLineEnd != std::string::npos) diagnostic.erase(0, firstLineEnd + 1);
		}
		auto redactPath = [&](const std::string& path) {
			if (path.empty()) return;
			size_t position = 0;
			while ((position = diagnostic.find(path, position)) != std::string::npos) {
				diagnostic.replace(position, path.size(), "[path]");
				position += 6;
			}
		};
		redactPath(videoPath);
		redactPath(output);
		if (stderrTruncated && !diagnostic.empty()) {
			diagnostic.insert(0, "[earlier ffmpeg output omitted]\n");
		}
		return diagnostic;
	};

	int return_code = -1;
	const int join_result = subprocess_join(&proc, &return_code);
	subprocess_destroy(&proc);
	if (join_result != 0) {
		auto diagnostic = getStderrDiagnostic();
		if (diagnostic.empty()) {
			LOGF_ERROR("Could not wait for ffmpeg at '%s' while generating the waveform.", ffmpegPath.c_str());
		} else {
			LOGF_ERROR("Could not wait for ffmpeg at '%s' while generating the waveform. stderr:\n%s",
				ffmpegPath.c_str(), diagnostic.c_str());
		}
		return fail();
	}
	if (return_code != 0) {
		auto diagnostic = getStderrDiagnostic();
		if (diagnostic.empty()) {
			LOGF_ERROR("ffmpeg at '%s' failed to extract audio for the waveform (exit code %d).", ffmpegPath.c_str(), return_code);
		} else {
			LOGF_ERROR("ffmpeg at '%s' failed to extract audio for the waveform (exit code %d). stderr:\n%s",
				ffmpegPath.c_str(), return_code, diagnostic.c_str());
		}
		return fail();
	}

	if (!LoadFlac(output)) {
		auto diagnostic = getStderrDiagnostic();
		if (diagnostic.empty()) {
			LOGF_ERROR("ffmpeg at '%s' did not produce readable audio for the waveform.", ffmpegPath.c_str());
		} else {
			LOGF_ERROR("ffmpeg at '%s' did not produce readable audio for the waveform. stderr:\n%s",
				ffmpegPath.c_str(), diagnostic.c_str());
		}
		return fail();
	}

	generating = false;
	return true;
}

void OFS_WaveformLOD::Init() noexcept
{
	glGenTextures(1, &WaveformTex);
	glBindTexture(GL_TEXTURE_2D, WaveformTex);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE); 
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	WaveShader = std::make_unique<WaveformShader>();
}

void OFS_WaveformLOD::Update(const OverlayDrawingCtx& ctx) noexcept
{
	OFS_PROFILE(__FUNCTION__);
	const float relStart = ctx.offsetTime / ctx.totalDuration;
	const float relDuration = ctx.visibleTime / ctx.totalDuration;
	
	const auto& samples = data.Samples();
	const float totalSampleCount = samples.size();

	float startIndexF = relStart * totalSampleCount;
	float endIndexF = (relStart* totalSampleCount) + (totalSampleCount * relDuration);

	float visibleSampleCountF = endIndexF - startIndexF;

	const float desiredSamples = ctx.canvasSize.x/3.f;
	const float everyNth = SDL_ceilf(visibleSampleCountF / desiredSamples);

	auto& lineBuf = WaveformLineBuffer;		
	if((int32_t)lastMultiple != (int32_t)(startIndexF / everyNth)) {
		int32_t scrollBy = (startIndexF/everyNth) - lastMultiple;

		if(lastVisibleDuration == ctx.visibleTime
		&& lastCanvasX == ctx.canvasSize.x
		&& scrollBy > 0 && scrollBy < lineBuf.size()) {
			OFS_PROFILE("WaveformScrolling");
			std::memcpy(lineBuf.data(), lineBuf.data() + scrollBy, sizeof(float) * (lineBuf.size() - scrollBy));
			lineBuf.resize(lineBuf.size() - scrollBy);
			
			int addedCount = 0;
			float maxSample;
			for(int32_t i = endIndexF - (everyNth*scrollBy); i <= endIndexF; i += everyNth) {
				maxSample = 0.f;
				for(int32_t j=0; j < everyNth; j += 1) {
					int32_t currentIndex = i + j;
					if(currentIndex >= 0 && currentIndex < totalSampleCount) {
						float s = std::abs(samples[currentIndex]);
						maxSample = Util::Max(maxSample, s);
					}
				}
				lineBuf.emplace_back(maxSample);
				addedCount += 1; 
				if(addedCount == scrollBy) break;
			}
			assert(addedCount == scrollBy);
		} else if(scrollBy != 0) {
			OFS_PROFILE("WaveformUpdate");
			lineBuf.clear();
			float maxSample;
			for(int32_t i = startIndexF; i <= endIndexF; i += everyNth) {
				maxSample = 0.f;
				for(int32_t j=0; j < everyNth; j += 1) {
					int32_t currentIndex = i + j;
					if(currentIndex >= 0 && currentIndex < totalSampleCount) {
						float s = std::abs(samples[currentIndex]);
						maxSample = Util::Max(maxSample, s);
					}
				}
				lineBuf.emplace_back(maxSample);
			}
		}

		
		lastMultiple = SDL_floorf(startIndexF / everyNth);
		lastCanvasX = ctx.canvasSize.x;
		lastVisibleDuration = ctx.visibleTime;
		Upload();
	}

	samplingOffset = (1.f / lineBuf.size()) * ((startIndexF/everyNth) - lastMultiple);

#if 0
	ImGui::Begin("Waveform Debug");
	ImGui::Text("Audio samples: %lld", lineBuf.size());
	ImGui::Text("Expected samples: %f", (endIndexF - startIndexF)/everyNth);
	ImGui::Text("Samples in view: %f", (endIndexF - startIndexF));
	ImGui::Text("Start: %f", startIndexF);
	ImGui::Text("End: %f", endIndexF);
	ImGui::Text("Every nth: %f", everyNth);
	ImGui::Text("Last multiple: %f", lastMultiple);
	ImGui::SliderFloat("Offset", &samplingOffset, 0.f, 1.f/lineBuf.size(), "%f");
	ImGui::End();
#endif
}

void OFS_WaveformLOD::Upload() noexcept
{
	OFS_PROFILE(__FUNCTION__);
	glActiveTexture(GL_TEXTURE1);
	glBindTexture(GL_TEXTURE_2D, WaveformTex);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_R32F, WaveformLineBuffer.size(), 1, 0, GL_RED, GL_FLOAT, WaveformLineBuffer.data());
}
