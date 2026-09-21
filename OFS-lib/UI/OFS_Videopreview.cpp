#include "OFS_Videopreview.h"

#include "OFS_Profiling.h"

VideoPreview::VideoPreview(bool hwAccel) noexcept
{
	player = std::make_unique<OFS_Videoplayer>(VideoplayerType::Preview);
	player->Init(hwAccel);
}

VideoPreview::~VideoPreview() noexcept
{
}

void VideoPreview::Init() noexcept
{
	player->SetVolume(0.f);
}

void VideoPreview::Update(float delta) noexcept
{
	OFS_PROFILE(__FUNCTION__);
	if (!videoOpened) return;
	player->Update(delta);
}

void VideoPreview::SetVideoPath(const std::string& path) noexcept
{
	OFS_PROFILE(__FUNCTION__);
	if (videoPath == path) return;
	if (videoOpened) {
		player->CloseVideo();
	}
	videoPath = path;
	videoOpened = false;
}

void VideoPreview::PreviewVideo(float pos) noexcept
{
	OFS_PROFILE(__FUNCTION__);
	if (videoPath.empty()) return;
	if (!videoOpened) {
		player->OpenVideo(videoPath);
		player->SetVolume(0.f);
		videoOpened = true;
	}
	player->SetPositionPercent(pos);
}

void VideoPreview::Play() noexcept
{
	OFS_PROFILE(__FUNCTION__);
	if (!videoOpened) return;
	player->SetPaused(false);
}

void VideoPreview::Pause() noexcept
{
	OFS_PROFILE(__FUNCTION__);
	if (!videoOpened) return;
	player->SetPaused(true);
}

void VideoPreview::CloseVideo() noexcept
{
	if (!videoOpened) return;
	player->CloseVideo();
	videoOpened = false;
}
