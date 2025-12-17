<template>
  <view class="container">
    <view class="header">
      <text class="title">AI 魔法消除</text>
      <text class="subtitle">涂抹水印，智能重绘</text>
    </view>

    <view v-if="step === 'upload'" class="upload-zone" @click="chooseImage">
      <image src="/static/upload-icon.png" class="upload-icon" mode="widthFix" />
      <text class="upload-text">点击上传图片</text>
      <text class="upload-sub">支持 JPG/PNG，去水印效果更好</text>
    </view>

    <view v-else-if="step === 'paint'" class="paint-zone">
      <view class="canvas-wrapper" :style="{ width: imgWidth + 'px', height: imgHeight + 'px' }">
        <image :src="originalImage" class="bg-img" :style="{ width: imgWidth + 'px', height: imgHeight + 'px' }" />
        
        <canvas 
          canvas-id="maskCanvas" 
          id="maskCanvas"
          class="mask-canvas"
          :style="{ width: imgWidth + 'px', height: imgHeight + 'px' }"
          @touchstart="touchStart"
          @touchmove="touchMove"
          @touchend="touchEnd"
          disable-scroll="true"
        ></canvas>
      </view>

      <view class="paint-tools">
        <view class="tool-info">请涂抹覆盖水印区域</view>
        <view class="tool-btns">
          <button class="btn mini" @click="clearCanvas">重涂</button>
          <button class="btn primary" @click="submitProcess" :loading="loading">开始消除</button>
        </view>
      </view>
    </view>

    <view v-else-if="step === 'result'" class="compare-zone">
      <view 
        class="compare-container" 
        :style="{ width: imgWidth + 'px', height: imgHeight + 'px' }"
        @touchstart="handleSliderStart" 
        @touchmove="handleSliderMove"
      >
        <image :src="processedImage" class="result-img full-size" mode="aspectFill" />
        
        <view class="top-img-wrapper" :style="{ width: sliderPosition + '%' }">
          <image :src="originalImage" class="full-size" mode="aspectFill" />
          <view class="label original-label">原图</view>
        </view>

        <view class="slider-bar" :style="{ left: sliderPosition + '%' }">
          <view class="slider-btn"><text class="arrow">↔</text></view>
        </view>
        
        <view class="label result-label">修复后</view>
      </view>

      <view class="action-area">
        <button class="btn secondary" @click="reset">重新上传</button>
        <button class="btn primary" @click="saveImage">保存相册</button>
      </view>
    </view>

    <view v-if="loading" class="loading-mask">
      <view class="spinner"></view>
      <text class="loading-text">AI 正在重绘画面...</text>
    </view>

  </view>
</template>

<script setup>
import { ref, nextTick } from 'vue';

// ================= 配置区 =================
// 请替换为你服务器的真实 IP
const BASE_URL = 'http://111.231.120.121:3001'; 
const API_URL = `${BASE_URL}/api/remove-watermark`;

// ================= 状态变量 =================
const step = ref('upload'); // 当前步骤: upload | paint | result
const originalImage = ref('');
const processedImage = ref('');
const loading = ref(false);

// 图片尺寸适配
const imgWidth = ref(300);
const imgHeight = ref(300);

// 画布上下文
let ctx = null;

// 对比滑块
const sliderPosition = ref(50);

// ================= 1. 图片选择与适配 =================
const chooseImage = () => {
  uni.chooseImage({
    count: 1,
    sizeType: ['compressed'],
    success: (res) => {
      const filePath = res.tempFilePaths[0];
      originalImage.value = filePath;
      
      // 获取图片信息以计算画布尺寸
      uni.getImageInfo({
        src: filePath,
        success: (image) => {
          calculateCanvasSize(image.width, image.height);
          step.value = 'paint';
          
          // 初始化画布
          nextTick(() => {
            initCanvas();
          });
        }
      });
    }
  });
};

// 计算适配屏幕的画布尺寸
const calculateCanvasSize = (w, h) => {
  const sysInfo = uni.getSystemInfoSync();
  const maxWidth = sysInfo.windowWidth - 40; // 左右留边距
  const maxHeight = sysInfo.windowHeight * 0.6; // 最大高度占屏 60%
  
  let scale = 1;
  if (w > maxWidth || h > maxHeight) {
    scale = Math.min(maxWidth / w, maxHeight / h);
  }
  
  imgWidth.value = w * scale;
  imgHeight.value = h * scale;
};

// ================= 2. 画布涂抹逻辑 =================
const initCanvas = () => {
  ctx = uni.createCanvasContext('maskCanvas');
  // 设置画笔样式
  ctx.setLineCap('round');
  ctx.setLineJoin('round');
  ctx.setLineWidth(20); // 笔触粗细，可以做成滑块调节
  
  // 关键：我们要生成蒙版。
  // 前端显示：背景半透明黑，画笔白色（白色代表 Mask 区域）
  // 这样导出的图片：背景透明（或黑），笔迹白。正是 LaMa 需要的 Mask。
  
  // 填充一个半透明黑色背景，方便用户看清原图
  // 注意：实际导出给后端的 Mask 应该是 黑底白画。
  // 但 uni-app canvas 导出带 alpha 通道。
  // 我们这里只画笔触。为了视觉效果，我们在 CSS 里给 canvas 加了个半透明背景。
  
  ctx.setStrokeStyle('rgba(255, 255, 255, 0.8)'); // 半透明白，方便看
};

const touchStart = (e) => {
  if (!ctx) return;
  const { x, y } = e.touches[0];
  ctx.moveTo(x, y);
  ctx.beginPath(); // 修复部分真机上笔画连在一起的问题
};

const touchMove = (e) => {
  if (!ctx) return;
  const { x, y } = e.touches[0];
  ctx.lineTo(x, y);
  ctx.stroke();
  ctx.draw(true); // true 表示保留之前的内容
};

const touchEnd = () => {
  // 可以在这里保存一下历史记录做撤销功能
};

const clearCanvas = () => {
  if (!ctx) return;
  ctx.clearRect(0, 0, imgWidth.value, imgHeight.value);
  ctx.draw();
};

// ================= 3. 提交与处理 (核心难点) =================
const submitProcess = () => {
  loading.value = true;

  // 1. 将画布导出为图片文件 (Mask)
  uni.canvasToTempFilePath({
    canvasId: 'maskCanvas',
    fileType: 'png',
    width: imgWidth.value,
    height: imgHeight.value,
    destWidth: imgWidth.value, // 保持清晰度，可 * 2
    destHeight: imgHeight.value,
    success: (res) => {
      const maskPath = res.tempFilePath;
      uploadFiles(originalImage.value, maskPath);
    },
    fail: (err) => {
      loading.value = false;
      uni.showToast({ title: '生成蒙版失败', icon: 'none' });
    }
  });
};

// 2. 上传两个文件 (原图 + 蒙版)
// 注意：H5 和 App 处理方式不同，这里使用 H5 兼容性最好的 fetch 方式
// 如果是小程序，需要使用 uni.uploadFile 的 files 参数 (部分平台不支持) 或者分别上传
const uploadFiles = async (imagePath, maskPath) => {
  
  // #ifdef H5
  try {
    const formData = new FormData();
    // 将文件路径转换为 Blob (H5特有操作)
    const imageBlob = await urlToBlob(imagePath);
    const maskBlob = await urlToBlob(maskPath);
    
    formData.append('image', imageBlob, 'image.png');
    formData.append('mask', maskBlob, 'mask.png');

    const response = await fetch(API_URL, {
      method: 'POST',
      body: formData
    });

    if (!response.ok) throw new Error('Server Error');

    // 处理二进制流返回图片
    const resultBlob = await response.blob();
    const resultUrl = URL.createObjectURL(resultBlob);
    
    handleSuccess(resultUrl);

  } catch (error) {
    console.error(error);
    loading.value = false;
    uni.showToast({ title: '处理失败，请检查网络', icon: 'none' });
  }
  // #endif

  // #ifndef H5
  // APP/小程序端：uni.uploadFile 不太好直接传两个文件且接收二进制流
  // 建议：如果必须支持 APP，建议后端改一下，先存文件返回 URL。
  // 这里尝试用 uni.uploadFile 传多文件 (仅部分支持) 或者 单独逻辑
  uni.showToast({ title: '目前演示仅支持 H5 环境', icon: 'none' });
  loading.value = false;
  // #endif
};

// H5 工具：URL 转 Blob
const urlToBlob = (url) => {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('GET', url, true);
    xhr.responseType = 'blob';
    xhr.onload = () => {
      if (xhr.status === 200) resolve(xhr.response);
      else reject(new Error('转换失败'));
    };
    xhr.onerror = reject;
    xhr.send();
  });
};

const handleSuccess = (url) => {
  processedImage.value = url;
  loading.value = false;
  step.value = 'result';
  sliderPosition.value = 100;
  
  // 自动演示一下对比
  setTimeout(() => {
    let pos = 100;
    const timer = setInterval(() => {
      pos -= 2;
      sliderPosition.value = pos;
      if(pos <= 50) clearInterval(timer);
    }, 10);
  }, 500);
};

// ================= 4. 结果页逻辑 =================
const handleSliderStart = () => {};
const handleSliderMove = (e) => {
  const sysInfo = uni.getSystemInfoSync();
  const screenWidth = sysInfo.windowWidth; 
  // 简单计算，假设居中
  let clientX = e.touches[0].clientX;
  // 修正 margin (40rpx approx 20px)
  let rectLeft = (screenWidth - imgWidth.value) / 2;
  
  let percent = ((clientX - rectLeft) / imgWidth.value) * 100;
  if(percent < 0) percent = 0;
  if(percent > 100) percent = 100;
  sliderPosition.value = percent;
};

const reset = () => {
  step.value = 'upload';
  processedImage.value = '';
  originalImage.value = '';
};

const saveImage = () => {
  // #ifdef H5
  const link = document.createElement('a');
  link.href = processedImage.value;
  link.download = `removed_watermark_${Date.now()}.png`;
  link.click();
  // #endif
};

</script>

<style lang="scss">
.container {
  min-height: 100vh;
  background: #f8f9fa;
  padding: 30rpx;
  display: flex;
  flex-direction: column;
  align-items: center;
}

.header {
  margin: 40rpx 0;
  text-align: center;
  .title { font-size: 40rpx; font-weight: bold; color: #333; display: block; }
  .subtitle { font-size: 26rpx; color: #888; margin-top: 10rpx; display: block; }
}

/* 1. 上传区 */
.upload-zone {
  width: 100%;
  height: 500rpx;
  background: #fff;
  border-radius: 24rpx;
  border: 4rpx dashed #ddd;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  
  .upload-icon { width: 100rpx; height: 100rpx; margin-bottom: 20rpx; }
  .upload-text { font-size: 32rpx; color: #333; font-weight: 500; }
  .upload-sub { font-size: 24rpx; color: #aaa; margin-top: 10rpx; }
}

/* 2. 涂抹区 */
.paint-zone {
  display: flex;
  flex-direction: column;
  align-items: center;
  
  .canvas-wrapper {
    position: relative;
    box-shadow: 0 10rpx 30rpx rgba(0,0,0,0.1);
    border-radius: 12rpx;
    overflow: hidden;
    background: #000; /* 底色黑 */
  }
  
  .bg-img {
    position: absolute;
    top: 0; left: 0;
    z-index: 1;
  }
  
  .mask-canvas {
    position: absolute;
    top: 0; left: 0;
    z-index: 10;
    /* 这里的背景色只是为了让用户看到图片变暗，从而看清白色的笔迹 */
    background: rgba(0, 0, 0, 0.4); 
  }
  
  .paint-tools {
    width: 100%;
    margin-top: 30rpx;
    
    .tool-info {
      text-align: center;
      color: #666;
      font-size: 28rpx;
      margin-bottom: 20rpx;
    }
    
    .tool-btns {
      display: flex;
      gap: 20rpx;
      
      .btn {
        border-radius: 50rpx;
        font-size: 30rpx;
        &.mini { width: 200rpx; background: #fff; color: #333; border: 1px solid #ddd; }
        &.primary { flex: 1; background: #007aff; color: #fff; }
      }
    }
  }
}

/* 3. 结果对比区 */
.compare-zone {
  display: flex;
  flex-direction: column;
  align-items: center;
  
  .compare-container {
    position: relative;
    border-radius: 12rpx;
    overflow: hidden;
    box-shadow: 0 10rpx 30rpx rgba(0,0,0,0.15);
  }
  
  .full-size { width: 100%; height: 100%; display: block; }
  
  .result-img { position: absolute; top:0; left:0; z-index: 1; }
  
  .top-img-wrapper {
    position: absolute;
    top: 0; left: 0;
    height: 100%;
    z-index: 2;
    overflow: hidden;
    border-right: 2px solid #fff;
    background: #fff; /* 防止透明图穿透 */
  }
  
  .slider-bar {
    position: absolute;
    top: 0; bottom: 0;
    width: 40rpx; /* 加宽增加触摸区域 */
    transform: translateX(-50%);
    z-index: 10;
    display: flex;
    align-items: center;
    justify-content: center;
    
    .slider-btn {
      width: 60rpx; height: 60rpx;
      background: #fff;
      border-radius: 50%;
      box-shadow: 0 4rpx 10rpx rgba(0,0,0,0.3);
      text-align: center;
      line-height: 60rpx;
      color: #333;
      font-weight: bold;
    }
  }
  
  .label {
    position: absolute; bottom: 20rpx;
    padding: 4rpx 12rpx; background: rgba(0,0,0,0.6);
    color: #fff; font-size: 22rpx; border-radius: 8rpx;
  }
  .original-label { left: 20rpx; }
  .result-label { right: 20rpx; z-index: 1; }
  
  .action-area {
    margin-top: 40rpx;
    width: 100%;
    display: flex;
    gap: 30rpx;
    .btn { flex: 1; border-radius: 50rpx; }
    .secondary { background: #fff; border: 1px solid #ddd; }
    .primary { background: #007aff; color: #fff; }
  }
}

/* Loading 蒙层 */
.loading-mask {
  position: fixed;
  top: 0; left: 0; right: 0; bottom: 0;
  background: rgba(255,255,255,0.9);
  z-index: 999;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  
  .spinner {
    width: 60rpx; height: 60rpx;
    border: 6rpx solid #eee;
    border-top-color: #007aff;
    border-radius: 50%;
    animation: spin 1s linear infinite;
    margin-bottom: 20rpx;
  }
  .loading-text { color: #333; font-size: 30rpx; font-weight: 500; }
}

@keyframes spin { 100% { transform: rotate(360deg); } }
</style>