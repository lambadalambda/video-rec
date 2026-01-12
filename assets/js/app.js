// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/video_suggestion"
import topbar from "../vendor/topbar"

const VideoFeed = {
  mounted() {
    this.feedItems = []
    this.videos = []
    this.activeIndex = 0
    this.activeVideoEl = null
    this.loadingMore = false
    this.observedVideos = new Set()

    this.prevButton = this.el.querySelector("[data-feed-prev]")
    this.nextButton = this.el.querySelector("[data-feed-next]")

    this.playToggle = this.el.querySelector("[data-feed-play-toggle]")
    this.playIcon = this.el.querySelector("[data-feed-play-icon]")
    this.pauseIcon = this.el.querySelector("[data-feed-pause-icon]")
    this.userPaused = false
    this.updatePlayUI()

    this.soundToggle = this.el.querySelector("[data-feed-sound-toggle]")
    this.soundIconOn = this.el.querySelector("[data-feed-sound-on]")
    this.soundIconOff = this.el.querySelector("[data-feed-sound-off]")

    this.soundOn = localStorage.getItem("vs:sound") === "on"
    this.updateSoundUI()

    this.onPrev = e => {
      e.preventDefault()
      this.scrollBy(-1)
    }

    this.onNext = e => {
      e.preventDefault()
      this.scrollBy(1)
    }

    this.onSoundToggle = e => {
      e.preventDefault()
      this.soundOn = !this.soundOn
      localStorage.setItem("vs:sound", this.soundOn ? "on" : "off")
      this.updateSoundUI()
      this.applySoundToActiveVideo()
    }

    this.onPlayToggle = e => {
      e.preventDefault()
      this.userPaused = !this.userPaused
      this.updatePlayUI()

      const video = this.videos[this.activeIndex]
      if (!video) return

      if (this.userPaused) {
        video.pause()
      } else {
        this.applySoundToVideo(video)
        video.play().catch(() => {})
      }
    }

    this.onKeyDown = e => {
      if (e.defaultPrevented) return

      if (e.target && ["INPUT", "TEXTAREA", "SELECT"].includes(e.target.tagName)) return

      if (e.key === "ArrowDown" || e.key === "PageDown") {
        e.preventDefault()
        this.scrollBy(1)
      } else if (e.key === "ArrowUp" || e.key === "PageUp") {
        e.preventDefault()
        this.scrollBy(-1)
      }
    }

    this.observer = new IntersectionObserver(
      entries => {
        for (const entry of entries) {
          const video = entry.target
          if (entry.isIntersecting && entry.intersectionRatio >= 0.75) {
            this.setActiveVideo(video)
          } else {
            video.pause()
            video.muted = true
          }
        }
      },
      {root: this.el, threshold: [0, 0.75, 1]},
    )

    this.syncElements()
    this.observeVideos()

    if (this.hasPrevClone) {
      this.activeIndex = this.firstRealIndex
      this.scrollToIndex(this.firstRealIndex, "auto")
    }

    this.prevButton?.addEventListener("click", this.onPrev)
    this.nextButton?.addEventListener("click", this.onNext)
    this.playToggle?.addEventListener("click", this.onPlayToggle)
    this.soundToggle?.addEventListener("click", this.onSoundToggle)
    window.addEventListener("keydown", this.onKeyDown)
  },

  updated() {
    const previousActiveVideoEl = this.activeVideoEl
    const previousActiveIndex = this.activeIndex

    this.syncElements()
    this.observeVideos()

    if (previousActiveVideoEl) {
      const item = previousActiveVideoEl.closest("[data-feed-item]")
      const index = item ? this.feedItems.indexOf(item) : -1

      if (index >= 0) {
        this.activeIndex = index
      } else {
        this.activeIndex = this.clampIndex(previousActiveIndex)
      }
    } else {
      this.activeIndex = this.clampIndex(previousActiveIndex)
    }

    this.applySoundToActiveVideo()
    this.maybeRequestMore()
  },

  syncElements() {
    this.feedItems = Array.from(this.el.querySelectorAll("[data-feed-item]"))
    this.videos = this.feedItems
      .map(item => item.querySelector("video[data-feed-video]"))
      .filter(Boolean)

    this.hasPrevClone = this.feedItems[0]?.dataset.feedClone === "prev"
    this.hasNextClone = this.feedItems[this.feedItems.length - 1]?.dataset.feedClone === "next"

    this.firstRealIndex = this.hasPrevClone ? 1 : 0
    this.lastRealIndex = this.hasNextClone ? this.feedItems.length - 2 : this.feedItems.length - 1
  },

  observeVideos() {
    this.videos.forEach(video => {
      if (!this.observedVideos.has(video)) {
        this.observedVideos.add(video)
        this.observer.observe(video)
      }
    })
  },

  hasMore() {
    return this.el.dataset.feedHasMore === "true"
  },

  maybeRequestMore() {
    if (!this.hasMore()) return
    if (this.loadingMore) return
    if (this.activeIndex < this.lastRealIndex - 1) return

    this.loadingMore = true
    this.pushEvent("load-more", {})
    window.setTimeout(() => this.loadingMore = false, 500)
  },

  scrollBy(delta) {
    const nextIndex = this.clampIndex(this.activeIndex + delta)
    this.scrollToIndex(nextIndex)
  },

  scrollToIndex(index, behavior = "smooth") {
    const item = this.feedItems[index]
    if (!item) return

    item.scrollIntoView({behavior, block: "start", inline: "nearest"})
  },

  clampIndex(index) {
    return Math.min(this.feedItems.length - 1, Math.max(0, index))
  },

  setActiveVideo(video) {
    const item = video.closest("[data-feed-item]")
    const index = item ? this.feedItems.indexOf(item) : -1
    if (index < 0) return

    const clone = item.dataset.feedClone
    if (clone === "prev") {
      const targetIndex = this.lastRealIndex
      this.userPaused = false
      this.updatePlayUI()
      this.activeIndex = targetIndex
      video.pause()
      video.muted = true
      this.scrollToIndex(targetIndex, "auto")
      return
    }

    if (clone === "next") {
      const targetIndex = this.firstRealIndex
      this.userPaused = false
      this.updatePlayUI()
      this.activeIndex = targetIndex
      video.pause()
      video.muted = true
      this.scrollToIndex(targetIndex, "auto")
      return
    }

    const changed = index !== this.activeIndex
    this.activeIndex = index
    this.activeVideoEl = video
    if (changed) {
      this.userPaused = false
      this.updatePlayUI()
    }

    this.applySoundToVideo(video)
    if (!this.userPaused) {
      video.play().catch(() => {})
    }

    this.preloadIndex(this.activeIndex + 1)
    this.preloadIndex(this.activeIndex - 1)
    this.maybeRequestMore()
  },

  applySoundToVideo(video) {
    if (!video) return
    video.muted = !this.soundOn
  },

  applySoundToActiveVideo() {
    const video = this.videos[this.activeIndex]
    if (!video) return

    this.applySoundToVideo(video)

    if (this.soundOn && !this.userPaused) {
      video.play().catch(() => {})
    }
  },

  updatePlayUI() {
    if (this.userPaused) {
      this.playIcon?.classList.remove("hidden")
      this.pauseIcon?.classList.add("hidden")
    } else {
      this.playIcon?.classList.add("hidden")
      this.pauseIcon?.classList.remove("hidden")
    }
  },

  updateSoundUI() {
    if (this.soundOn) {
      this.soundIconOn?.classList.remove("hidden")
      this.soundIconOff?.classList.add("hidden")
    } else {
      this.soundIconOn?.classList.add("hidden")
      this.soundIconOff?.classList.remove("hidden")
    }
  },

  preloadIndex(index) {
    if (index < 0 || index >= this.feedItems.length) return

    const item = this.feedItems[index]
    const video = item?.querySelector("video[data-feed-video]")
    if (!video || video.dataset.preloaded === "true") return

    video.dataset.preloaded = "true"
    video.preload = "auto"
    video.load()
  },
  destroyed() {
    this.observer?.disconnect()

    this.prevButton?.removeEventListener("click", this.onPrev)
    this.nextButton?.removeEventListener("click", this.onNext)
    this.playToggle?.removeEventListener("click", this.onPlayToggle)
    this.soundToggle?.removeEventListener("click", this.onSoundToggle)
    window.removeEventListener("keydown", this.onKeyDown)
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, VideoFeed},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
