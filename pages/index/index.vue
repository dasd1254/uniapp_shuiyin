<template>
  <view class="container">
    <view class="header">
      <text class="title">AI 魔法消除</text>
      <text class="subtitle">智能识别，一键无痕</text>
    </view>

    <view class="main-card">
      <view v-if="!originalImage" class="upload-zone" @click="chooseImage">
        <image src="/static/upload-icon.png" class="upload-icon" mode="widthFix" />
        <view class="icon-placeholder" v-if="false">+</view>
        <text class="upload-text">点击上传图片</text>
        <text class="upload-sub">支持 JPG/PNG，最大 50MB</text>
      </view>

      <view v-else class="compare-zone">
        <view 
          class="compare-container" 
          @touchstart="handleTouchStart" 
          @touchmove="handleTouchMove"
        >
          <image :src="displayImage" mode="aspectFit" class="bg-img" />
          
          <view 
            class="top-img-wrapper" 
            :style="{ width: isProcessed ? sliderPosition + '%' : '100%' }"
          >
            <image :src="originalImage" mode="aspectFit" class="top-img" />
            <view class="label original-label">原图</view>
          </view>

          <view 
            class="slider-bar" 
            v-if="isProcessed"
            :style="{ left: sliderPosition + '%' }"
          >
            <view class="slider-btn">
              <text class="arrow">↔</text>
            </view>
          </view>
          
          <view class="label result-label" v-if="isProcessed">去水印后</view>
        </view>
      </view>
    </view>

    <view class="action-area">
      <view v-if="loading" class="loading-box">
        <view class="spinner"></view>
        <text>AI 正在努力擦除中...</text>
      </view>

      <view v-else-if="originalImage && isProcessed" class="btn-group">
        <button class="btn secondary" @click="reset">重新上传</button>
        <button class="btn primary" @click="saveImage">保存到相册</button>
      </view>
      
      <view v-else-if="originalImage && !isProcessed" class="processing-hint">
          图片准备中...
       </view>
    </view>

    <view class="history-section" v-if="historyList.length > 0">
      <view class="section-title">
        <text>最近记录</text>
        <text class="clear-btn" @click="clearHistory">清空</text>
      </view>
      <scroll-view scroll-x class="history-scroll">
        <view class="history-item" v-for="(item, index) in historyList" :key="index" @click="loadFromHistory(item)">
          <image :src="item.result" mode="aspectFill" class="history-thumb" />
        </view>
      </scroll-view>
    </view>

  </view>
</template>

<script setup>
import { ref, computed } from 'vue';

// ================= 配置区 =================
// 必须改成 3001 端口
const BASE_URL = 'http://111.231.120.121:3001'; 
const API_URL = '/api/remove-watermark';

// ================= 状态变量 =================
const originalImage = ref('');    // 原图路径
const processedImage = ref('');   // 结果图路径
const loading = ref(false);
const sliderPosition = ref(50);   // 滑块位置 (0-100)
const historyList = ref(uni.getStorageSync('history_list') || []);

// 计算属性：是否处理完成
const isProcessed = computed(() => !!processedImage.value);
// 显示用的底图：如果有结果图就显示结果图，否则显示原图占位
const displayImage = computed(() => processedImage.value || originalImage.value);

// ================= 核心逻辑 =================

// 1. 选择图片
const chooseImage = () => {
  uni.chooseImage({
    count: 1,
    sizeType: ['compressed'], // 建议先压缩，加快上传
    success: (res) => {
      const filePath = res.tempFilePaths[0];
      originalImage.value = filePath;
      processedImage.value = ''; // 清空上次结果
      sliderPosition.value = 100; // 默认先全显示原图
      
      uploadAndProcess(filePath);
    }
  });
};

// 2. 上传处理 (复用健壮版逻辑)
const uploadAndProcess = (filePath) => {
  loading.value = true;
  
  uni.uploadFile({
    url: API_URL,
    filePath: filePath,
    name: 'file',
    success: (uploadFileRes) => {
      if (uploadFileRes.statusCode !== 200) {
        uni.showToast({ title: '服务器繁忙', icon: 'none' });
        loading.value = false;
        return;
      }
      
      try {
        const res = JSON.parse(uploadFileRes.data);
        if (res.code === 200) {
          const resultUrl = BASE_URL + res.data.url;
          // 图片预加载：创建一个隐藏的 image 对象，等加载完再显示，防止闪烁
          // UniApp 中简单处理：
          processedImage.value = resultUrl;
          loading.value = false;
          
          // 自动滑动演示效果
          autoAnimateSlider();
          
          // 加入历史记录
          addToHistory(originalImage.value, resultUrl);
          
        } else {
          uni.showToast({ title: res.msg || '处理失败', icon: 'none' });
          loading.value = false;
        }
      } catch (e) {
        loading.value = false;
        uni.showToast({ title: '数据解析错误', icon: 'none' });
      }
    },
    fail: () => {
      loading.value = false;
      uni.showToast({ title: '网络错误', icon: 'none' });
    }
  });
};

// 3. 滑动对比逻辑
const handleTouchStart = (e) => {
  // 禁止页面滚动
};
const handleTouchMove = (e) => {
  if (!isProcessed.value) return;
  
  // 获取触摸点相对于屏幕宽度的百分比
  const screenWidth = uni.getSystemInfoSync().windowWidth;
  // 主要容器有 margin，这里简单按全屏估算，更精确做法是用 uni.createSelectorQuery
  // 这里为了 Demo 简单化，假设容器几乎占满屏幕宽
  let touchX = e.touches[0].clientX;
  
  // 限制范围 0-100
  let percent = (touchX / screenWidth) * 100;
  if (percent < 0) percent = 0;
  if (percent > 100) percent = 100;
  
  sliderPosition.value = percent;
};

// 4. 自动演示滑动效果 (提升体验)
const autoAnimateSlider = () => {
  sliderPosition.value = 100;
  // 简单的动画逻辑：从 100 滑到 50
  let start = 100;
  const timer = setInterval(() => {
    start -= 2;
    sliderPosition.value = start;
    if (start <= 50) clearInterval(timer);
  }, 10);
};

// 5. 保存图片
const saveImage = () => {
  // #ifdef H5
  uni.showToast({ title: '请长按图片保存', icon: 'none' });
  // #endif

  // #ifndef H5
  uni.saveImageToPhotosAlbum({
    filePath: processedImage.value,
    success: () => uni.showToast({ title: '已保存', icon: 'success' }),
    fail: () => uni.showToast({ title: '保存失败，请授权相册权限', icon: 'none' })
  });
  // #endif
};

// 6. 重置
const reset = () => {
  originalImage.value = '';
  processedImage.value = '';
  sliderPosition.value = 50;
};

// 7. 历史记录管理
const addToHistory = (original, result) => {
  const item = { original, result, time: Date.now() };
  // 放在最前面
  historyList.value.unshift(item);
  // 只保留最近 10 条
  if (historyList.value.length > 10) historyList.value.pop();
  uni.setStorageSync('history_list', historyList.value);
};

const loadFromHistory = (item) => {
  originalImage.value = item.original;
  processedImage.value = item.result;
  sliderPosition.value = 50;
};

const clearHistory = () => {
  historyList.value = [];
  uni.removeStorageSync('history_list');
};
</script>

<style lang="scss">
/* 页面背景 */
.container {
  min-height: 100vh;
  background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
  padding: 40rpx;
  display: flex;
  flex-direction: column;
  align-items: center;
}

/* 标题 */
.header {
  margin-bottom: 40rpx;
  text-align: center;
  
  .title {
    font-size: 48rpx;
    font-weight: bold;
    color: #333;
    display: block;
    margin-bottom: 10rpx;
  }
  .subtitle {
    font-size: 28rpx;
    color: #666;
    letter-spacing: 2rpx;
  }
}

/* 主卡片 (核心区域) */
.main-card {
  width: 100%;
  height: 600rpx;
  background: #fff;
  border-radius: 30rpx;
  box-shadow: 0 10rpx 30rpx rgba(0,0,0,0.1);
  overflow: hidden;
  position: relative;
  display: flex;
  justify-content: center;
  align-items: center;
}

/* 上传态 */
.upload-zone {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  width: 100%;
  height: 100%;
  
  .upload-icon {
    width: 120rpx;
    height: 120rpx;
    margin-bottom: 20rpx;
  }
  .upload-text {
    font-size: 34rpx;
    font-weight: 500;
    color: #333;
  }
  .upload-sub {
    font-size: 24rpx;
    color: #999;
    margin-top: 10rpx;
  }
}

/* 对比态 (重叠布局) */
.compare-zone {
  width: 100%;
  height: 100%;
}

.compare-container {
  position: relative;
  width: 100%;
  height: 100%;
}

.bg-img, .top-img {
  width: 100%;
  height: 100%;
  display: block;
}

/* 顶层图片容器 (用于裁剪) */
.top-img-wrapper {
  position: absolute;
  top: 0;
  left: 0;
  height: 100%;
  overflow: hidden; /* 关键：超出宽度的部分隐藏 */
  border-right: 2px solid rgba(255, 255, 255, 0.8); /* 分割线 */
  z-index: 10;
}

/* 滑块控制器 */
.slider-bar {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 2px;
  z-index: 20;
  /* 这里的 left 由 style 动态控制 */
  
  .slider-btn {
    position: absolute;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    width: 60rpx;
    height: 60rpx;
    background: rgba(255, 255, 255, 0.9);
    border-radius: 50%;
    box-shadow: 0 4rpx 10rpx rgba(0,0,0,0.2);
    display: flex;
    align-items: center;
    justify-content: center;
    color: #333;
    font-size: 30rpx;
  }
}

/* 左下角/右下角标签 */
.label {
  position: absolute;
  bottom: 20rpx;
  padding: 6rpx 16rpx;
  background: rgba(0,0,0,0.5);
  color: #fff;
  font-size: 24rpx;
  border-radius: 8rpx;
  pointer-events: none;
}
.original-label { left: 20rpx; z-index: 15; }
.result-label { right: 20rpx; z-index: 5; }

/* 按钮区 */
.action-area {
  margin-top: 40rpx;
  width: 100%;
  min-height: 120rpx;
  display: flex;
  justify-content: center;
}

.btn-group {
  display: flex;
  gap: 30rpx;
  width: 100%;
}

.btn {
  flex: 1;
  height: 90rpx;
  line-height: 90rpx;
  border-radius: 45rpx;
  font-size: 32rpx;
  border: none;
  
  &.primary {
    background: #007aff;
    color: #fff;
    box-shadow: 0 8rpx 20rpx rgba(0, 122, 255, 0.3);
  }
  
  &.secondary {
    background: #fff;
    color: #333;
    border: 2rpx solid #eee;
  }
}

/* Loading 动画 */
.loading-box {
  display: flex;
  flex-direction: column;
  align-items: center;
  color: #666;
  font-size: 28rpx;
  
  .spinner {
    width: 40rpx;
    height: 40rpx;
    border: 4rpx solid #ddd;
    border-top: 4rpx solid #007aff;
    border-radius: 50%;
    animation: spin 1s linear infinite;
    margin-bottom: 16rpx;
  }
}

@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}

/* 历史记录 */
.history-section {
  width: 100%;
  margin-top: 60rpx;
  
  .section-title {
    display: flex;
    justify-content: space-between;
    font-size: 30rpx;
    font-weight: bold;
    color: #333;
    margin-bottom: 20rpx;
    
    .clear-btn {
      font-size: 24rpx;
      color: #999;
      font-weight: normal;
    }
  }
  
  .history-scroll {
    white-space: nowrap;
    width: 100%;
    
    .history-item {
      display: inline-block;
      width: 160rpx;
      height: 160rpx;
      margin-right: 20rpx;
      border-radius: 16rpx;
      overflow: hidden;
      border: 2rpx solid #fff;
      box-shadow: 0 4rpx 10rpx rgba(0,0,0,0.05);
      
      .history-thumb {
        width: 100%;
        height: 100%;
      }
    }
  }
}
</style>