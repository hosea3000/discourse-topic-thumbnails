import Component from "@glimmer/component";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { modifier } from "ember-modifier";
import coldAgeClass from "discourse/helpers/cold-age-class";
import concatClass from "discourse/helpers/concat-class";
import dIcon from "discourse/helpers/d-icon";
import formatDate from "discourse/helpers/format-date";

export default class TopicListThumbnail extends Component {
  @service topicThumbnails;
  @service("topic-content-loader") contentLoader;

  @tracked extractedImages = [];
  @tracked isLoading = false;
  @tracked hasLoaded = false;

  responsiveRatios = [1, 1.5, 2];

  // Make sure to update about.json thumbnail sizes if you change these variables
  get displayWidth() {
    return this.topicThumbnails.displayList
      ? settings.list_thumbnail_size
      : 400;
  }

  get topic() {
    return this.args.topic;
  }

  // Intersection Observer 用于检测元素是否进入视口
  intersectionObserver = null;

  get hasThumbnail() {
    if (this.topicThumbnails.displayBlogStyle) {
      // blog-style 模式：检查是否有提取的图片
      return this.imageUrls.length > 0;
    }
    // 其他模式：使用原有逻辑
    return !!this.topic.thumbnails;
  }

  async loadImages() {
    // 防止重复加载
    if (this.isLoading || this.hasLoaded) {
      return;
    }

    // blog-style 模式：从详情中加载图片
    if (this.topicThumbnails.displayBlogStyle) {
      const topicId = this.topic.id || this.topic.get?.("id");
      if (topicId) {
        this.isLoading = true;
        try {
          const images = await this.contentLoader.loadTopicImages(topicId);
          this.extractedImages = images;
          this.hasLoaded = true;
        } catch (error) {
          console.error(`Failed to load images for topic ${topicId}:`, error);
        } finally {
          this.isLoading = false;
        }
      }
    }
  }

  // 使用 Intersection Observer 检测元素是否进入视口
  setupIntersectionObserver = modifier((element) => {
    // 只在 blog-style 模式下使用懒加载
    if (!this.topicThumbnails.displayBlogStyle) {
      return;
    }

    // 如果已经加载过，直接返回
    if (this.hasLoaded) {
      return;
    }

    // 检查浏览器是否支持 Intersection Observer
    if (!window.IntersectionObserver) {
      // 如果不支持，直接加载
      this.loadImages();
      return;
    }

    // 创建 Intersection Observer
    this.intersectionObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          // 当元素进入视口时（至少 10% 可见），开始加载
          if (entry.isIntersecting && entry.intersectionRatio >= 0.1) {
            this.loadImages();
            // 加载后停止观察
            if (this.intersectionObserver) {
              this.intersectionObserver.unobserve(element);
            }
          }
        });
      },
      {
        // 当元素 10% 进入视口时触发
        threshold: 0.1,
        // 提前 100px 开始加载（预加载）
        rootMargin: "100px",
      }
    );

    // 开始观察元素
    this.intersectionObserver.observe(element);

    // 清理函数
    return () => {
      if (this.intersectionObserver) {
        this.intersectionObserver.disconnect();
        this.intersectionObserver = null;
      }
    };
  });

  get imageUrls() {

    if (this.topicThumbnails.displayBlogStyle) {
      // blog-style 模式：使用从详情中提取的图片
      return this.extractedImages;
    }
    
    // 其他模式：使用系统返回的缩略图
    if (this.topic.thumbnails && this.topic.thumbnails.length > 0) {
      return [this.topic.thumbnails[0].url];
    }

    return [];
  }

  get srcSet() {
    const srcSetArray = [];

    this.responsiveRatios.forEach((ratio) => {
      const target = ratio * this.displayWidth;
      const match = this.topic.thumbnails.find(
        (t) => t.url && t.max_width === target
      );
      if (match) {
        srcSetArray.push(`${match.url} ${ratio}x`);
      }
    });

    if (srcSetArray.length === 0) {
      srcSetArray.push(`${this.original.url} 1x`);
    }

    return srcSetArray.join(",");
  }

  get original() {
    return this.topic.thumbnails[0];
  }

  get width() {
    return this.original.width;
  }

  get isLandscape() {
    return this.original.width >= this.original.height;
  }

  get height() {
    return this.original.height;
  }

  get fallbackSrc() {
    const largeEnough = this.topic.thumbnails.filter((t) => {
      if (!t.url) {
        return false;
      }
      return t.max_width > this.displayWidth * this.responsiveRatios.lastObject;
    });

    if (largeEnough.lastObject) {
      return largeEnough.lastObject.url;
    }

    return this.original.url;
  }

  get url() {
    return this.topic.get("linked_post_number")
      ? this.topic.urlForPostNumber(this.topic.get("linked_post_number"))
      : this.topic.get("lastUnreadUrl");
  }

  get createdBy() {
    // posters 数组中的第一个通常是创建者
    if (this.topic.posters && this.topic.posters.length > 0) {
      return this.topic.posters[0];
    }

    return null;
  }

  get avatarUrl() {
    if (!this.createdBy) return null;
    let avatarTemplate = this.createdBy.user.avatar_template 
    
    if (!avatarTemplate) return null;
    
    // Discourse avatar template format: {size}/{version}.png
    // 需要替换 {size} 为实际大小
    if (avatarTemplate.includes("{size}")) {
      return avatarTemplate.replace("{size}", "40");
    }
    return avatarTemplate;
  }

  get posts_count() {
    return this.topic.posts_count - 1;
  }

  get username() {
    return this.topic.posters[0].user.username
  }

  get userUrl() {
    // 获取用户详情页 URL
    const username = this.username;
    if (username) {
      return `/u/${username}`;
    }
    return "#";
  }

  get createdAt() {
    // 尝试多种方式获取创建时间
    return (
      this.topic.created_at || (this.topic.get && this.topic.get("created_at"))
    );
  }

  <template>
    {{#if this.topicThumbnails.displayBlogStyle}}
      {{! Blog style 布局：顶部用户信息 + 底部图片 }}
      {{! 顶部：用户信息和互动指标 }}
      {{! 使用 modifier 设置 Intersection Observer，监听 header 元素（第一个可见元素）}}
      <div {{this.setupIntersectionObserver}} class="topic-thumbnail-blog-header">
        <div class="topic-thumbnail-blog-user-info">
          <a href={{this.userUrl}} class="topic-thumbnail-blog-avatar-link">
            <div class="topic-thumbnail-blog-avatar">
            {{#if this.avatarUrl}}
                <img src={{this.avatarUrl}} alt={{this.username}} />
            {{else}}
                {{dIcon "user"}}
            {{/if}}
            </div>
          </a>
          <div class="topic-thumbnail-blog-user-details">
            <a href={{this.userUrl}} class="topic-thumbnail-blog-username-link">
              <div class="topic-thumbnail-blog-username">
                  {{this.username}}
              </div>
            </a>
            {{#if this.createdAt}}
              <div class="topic-thumbnail-blog-date">
                {{~formatDate this.createdAt format="medium" noTitle="true"~}}
              </div>
            {{/if}}
          </div>
        </div>
        
        <div class="topic-thumbnail-blog-engagement">
          <div class="topic-thumbnail-blog-engagement-item">
            {{dIcon "comment"}}
            <span class="number">
              {{this.posts_count}}
            </span>
          </div>
          <div class="topic-thumbnail-blog-engagement-item">
            {{dIcon "heart"}}
            <span class="number">
              {{this.topic.like_count}}
            </span>
          </div>
        </div>
      </div>
 
      {{! 底部：图片区域 }}
      {{#if this.hasThumbnail}}
        <div class="topic-thumbnail-blog-images">
          {{#each this.imageUrls as |imageUrl|}}
            <div class="topic-list-thumbnail has-thumbnail">
              <a href={{this.url}} role="img" aria-label={{this.topic.title}}>
                <img
                  class="main-thumbnail"
                  src={{imageUrl}}
                  loading="lazy"
                  alt=""
                />
              </a>
            </div>
          {{/each}}
        </div>
      {{/if}}
    {{else}}
      {{! 其他布局模式：保持原有结构 }}
      <div
        class={{concatClass
          "topic-list-thumbnail"
          (if this.hasThumbnail "has-thumbnail" "no-thumbnail")
        }}
      >
        <a href={{this.url}} role="img" aria-label={{this.topic.title}}>
          {{#if this.hasThumbnail}}
            <img
              class="background-thumbnail"
              src={{this.fallbackSrc}}
              srcset={{this.srcSet}}
              width={{this.width}}
              height={{this.height}}
              loading="lazy"
              alt=""
            />
            <img
              class="main-thumbnail"
              src={{this.fallbackSrc}}
              srcset={{this.srcSet}}
              width={{this.width}}
              height={{this.height}}
              loading="lazy"
              alt=""
            />
          {{else}}
            <div class="thumbnail-placeholder">
              {{dIcon settings.placeholder_icon}}
            </div>
          {{/if}}
        </a>
      </div>

      {{#if this.topicThumbnails.showLikes}}
        <div class="topic-thumbnail-likes">
          {{dIcon "heart"}}
          <span class="number">
            {{this.topic.like_count}}
          </span>
        </div>
      {{/if}}
    {{/if}}
  </template>
}
