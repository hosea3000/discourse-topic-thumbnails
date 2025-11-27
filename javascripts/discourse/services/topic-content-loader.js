import Service from "@ember/service";

/**
 * 服务：用于加载 topic 的详细内容并解析图片
 * 使用请求队列控制并发，避免 429 错误
 */
export default class TopicContentLoaderService extends Service {
  // 请求队列
  requestQueue = [];
  // 正在进行的请求数量
  activeRequests = 0;
  // 最大并发数（减少到 1，避免过快）
  maxConcurrent = 1;
  // 请求间隔（毫秒，增加到 500ms）
  requestDelay = 300;
  // 缓存已加载的图片（包含过期时间）
  imageCache = new Map();
  // 缓存过期时间（毫秒），默认 5 分钟
  cacheExpiry = 5 * 60 * 1000; // 5 分钟

  /**
   * 从 HTML 中提取图片 URL
   */
  extractImagesFromHtml(html, maxImages = 3) {
    if (!html) return [];

    const tempDiv = document.createElement("div");
    tempDiv.innerHTML = html;
    const images = tempDiv.querySelectorAll("img");

    // 首先检查是否有 alt 包含"封面图"的图片
    for (let i = 0; i < images.length; i++) {
      const img = images[i];
      const alt = img.getAttribute("alt") || "";
      
      if (alt.includes("封面图")) {
        const src = img.getAttribute("src") || img.getAttribute("data-src");
        if (src) {
          let imageUrl = src;
          // 处理相对路径
          if (src.startsWith("/")) {
            imageUrl = window.location.origin + src;
          }

          // 排除表情符号、图标和头像
          if (
            !imageUrl.includes("/images/emoji/") &&
            !imageUrl.includes("/images/") &&
            !imageUrl.includes("avatar") &&
            !imageUrl.includes("user_avatar")
          ) {
            return [imageUrl]; // 直接返回封面图
          }
        }
      }
    }

    // 如果没有找到封面图，按原来的逻辑返回最多 maxImages 张图片
    const imageUrls = [];
    for (let i = 0; i < Math.min(images.length, maxImages); i++) {
      const img = images[i];
      const src = img.getAttribute("src") || img.getAttribute("data-src");

      if (src) {
        let imageUrl = src;
        // 处理相对路径
        if (src.startsWith("/")) {
          imageUrl = window.location.origin + src;
        }

        // 排除表情符号、图标和头像
        if (
          !imageUrl.includes("/images/emoji/") &&
          !imageUrl.includes("/images/") &&
          !imageUrl.includes("avatar") &&
          !imageUrl.includes("user_avatar")
        ) {
          imageUrls.push(imageUrl);
        }
      }
    }

    return imageUrls;
  }

  /**
   * 获取 topic 详情并提取图片（内部方法）
   */
  async _loadTopicImagesInternal(topicId) {
    try {
      // 使用 fetch API 请求 topic 详情接口
      const response = await fetch(`/t/${topicId}.json`, {
        method: "GET",
        headers: {
          "Content-Type": "application/json",
        },
        credentials: "same-origin",
      });

      if (!response.ok) {
        if (response.status === 429) {
          // 429 错误，大幅增加延迟
          this.requestDelay = Math.min(this.requestDelay * 2, 5000);
          this.maxConcurrent = 1; // 遇到 429 时强制单线程
          throw new Error("Rate limit exceeded");
        }
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();
      let images = [];

      // 从第一个 post 中提取图片
      if (result.post_stream && result.post_stream.posts && result.post_stream.posts.length > 0) {
        const firstPost = result.post_stream.posts[0];
        const cooked = firstPost.cooked;

        if (cooked) {
          // 提取图片（最多3张）
          images = this.extractImagesFromHtml(cooked, 3);
        }
      }

      // 缓存结果（包含时间戳）
      this.imageCache.set(topicId, {
        images,
        timestamp: Date.now(),
      });
      return images;
    } catch (error) {
      console.error(`Failed to load topic images for topic ${topicId}:`, error);
      return [];
    }
  }

  /**
   * 处理请求队列
   */
  async _processQueue() {
    // 如果队列为空或已达到最大并发数，返回
    if (this.requestQueue.length === 0 || this.activeRequests >= this.maxConcurrent) {
      return;
    }

    // 从队列中取出一个请求
    const { topicId, resolve, reject } = this.requestQueue.shift();
    this.activeRequests++;

    try {
      // 添加延迟，避免请求过快
      await new Promise((resolve) => setTimeout(resolve, this.requestDelay));
      
      const images = await this._loadTopicImagesInternal(topicId);
      resolve(images);
    } catch (error) {
      reject(error);
    } finally {
      this.activeRequests--;
      // 继续处理队列
      this._processQueue();
    }
  }

  /**
   * 检查缓存是否有效
   */
  _isCacheValid(cacheEntry) {
    if (!cacheEntry) return false;
    const now = Date.now();
    return now - cacheEntry.timestamp < this.cacheExpiry;
  }

  /**
   * 清理过期缓存
   */
  _cleanExpiredCache() {
    const now = Date.now();
    for (const [topicId, cacheEntry] of this.imageCache.entries()) {
      if (now - cacheEntry.timestamp >= this.cacheExpiry) {
        this.imageCache.delete(topicId);
      }
    }
  }

  /**
   * 获取 topic 详情并提取图片（公开方法，使用队列）
   */
  async loadTopicImages(topicId) {
    // 定期清理过期缓存
    this._cleanExpiredCache();

    // 检查缓存
    const cacheEntry = this.imageCache.get(topicId);
    if (cacheEntry && this._isCacheValid(cacheEntry)) {
      return cacheEntry.images;
    }

    // 如果缓存过期，删除它
    if (cacheEntry) {
      this.imageCache.delete(topicId);
    }

    // 返回 Promise，加入队列
    return new Promise((resolve, reject) => {
      this.requestQueue.push({ topicId, resolve, reject });
      this._processQueue();
    });
  }
}

