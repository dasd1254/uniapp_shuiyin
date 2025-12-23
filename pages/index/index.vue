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
      <view class="canvas-wrapper" id="finalCanvasWrapper" :style="{ width: imgWidth + 'px', height: imgHeight + 'px' }">
        <image :src="originalImage" class="bg-img" :style="{ width: imgWidth + 'px', height: imgHeight + 'px' }" />

        <canvas 
          v-if="canvasReady"
          canvas-id="maskCanvas" 
          id="maskCanvas"
          class="mask-canvas"
          :style="{ width: imgWidth + 'px', height: imgHeight + 'px' }"
          :width="imgWidth" 
          :height="imgHeight"
          
          @touchstart="handleStart"
          @touchmove="handleMove"
          @touchend="handleEnd"
          @mousedown="handleStart"
          disable-scroll="true"
        ></canvas>
      </view>

      <view class="paint-tools">
        <view class="tool-info">涂抹水印区域</view>
        <view class="slider-box">
          <text class="label">画笔大小</text>
          <slider :value="lineWidth" @change="e => lineWidth = e.detail.value" min="5" max="50"
            activeColor="#007aff" block-size="20" />
        </view>

        <view class="tool-btns">
          <button class="btn mini" @click="undo">撤销</button>
          <button class="btn mini" @click="clearCanvas">清空</button>
          <button class="btn primary" @click="submitProcess" :loading="loading">消除</button>
        </view>
      </view>
    </view>

    <view v-else-if="step === 'result'" class="compare-zone">
      <view class="compare-container" :style="{ width: imgWidth + 'px', height: imgHeight + 'px' }"
        @touchstart="handleSliderStart" @touchmove="handleSliderMove" @touchend="handleSliderEnd"
        @mousedown="handleSliderStart" @mousemove="handleSliderMove" @mouseup="handleSliderEnd"
        @mouseleave="handleSliderEnd">
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
      <view class="progress-box">
        <text class="loading-title">{{ loadingTitle }}</text>
        <view class="progress-bar-bg">
          <view class="progress-bar-fill" :style="{ width: progress + '%' }"></view>
        </view>
        <text class="progress-num">{{ Math.floor(progress) }}%</text>
        <text class="loading-tip">AI 正在努力计算像素，请稍候...</text>
      </view>
    </view>
  </view>
</template>

<script setup>
import { ref, nextTick, getCurrentInstance, onUnmounted } from 'vue';

const instance = getCurrentInstance();
const BASE_URL = 'http://111.231.120.121:3001'; 
const API_URL = `${BASE_URL}/api/remove-watermark`;

const step = ref('upload'); 
const originalImage = ref('');
const processedImage = ref('');
const loading = ref(false);

// 【核心修改1】初始值设为 0！解决 2000px 错位问题
const imgWidth = ref(0);
const imgHeight = ref(0); 
const canvasReady = ref(false); 

// 缩放比例：解决视差问题
const scaleX = ref(1);
const scaleY = ref(1);

let ctx = null;
const isDrawing = ref(false); 
const isSliderDragging = ref(false);
const sliderPosition = ref(50);

const lineWidth = ref(20);
const drawHistory = ref([]);
let currentPath = [];

const progress = ref(0);
const loadingTitle = ref('正在上传...');
let progressTimer = null;

const startFakeProgress = () => {
  progress.value = 0; loadingTitle.value = '正在上传图片...';
  if (progressTimer) clearInterval(progressTimer);
  progressTimer = setInterval(() => {
    if (progress.value < 30) progress.value += 2;
    else if (progress.value < 80) { progress.value += 0.5; loadingTitle.value = 'AI 正在智能识别水印...'; }
    else if (progress.value < 99) { progress.value += 0.1; loadingTitle.value = '正在进行深度重绘...'; }
  }, 50);
};
const stopFakeProgress = () => { if (progressTimer) clearInterval(progressTimer); };

// ================= 图片处理 =================
const chooseImage = () => {
  uni.chooseImage({
    count: 1, sizeType: ['compressed'],
    success: (res) => {
      const filePath = res.tempFilePaths[0];
      originalImage.value = filePath;
      canvasReady.value = false;
      
      uni.getImageInfo({
        src: filePath,
        success: (image) => {
          // 1. 计算逻辑尺寸
          calculateInitialSize(image.width, image.height);
          step.value = 'paint';
          
          // 2. 等待 DOM 渲染后，强制校准
          nextTick(() => {
            setTimeout(calibrateSize, 200);
          });
        }
      });
    }
  });
};

const calculateInitialSize = (w, h) => {
  const sysInfo = uni.getSystemInfoSync();
  const maxWidth = sysInfo.windowWidth - 40; 
  const maxHeight = sysInfo.windowHeight * 0.6; 
  let scale = 1;
  if (w > maxWidth || h > maxHeight) {
    scale = Math.min(maxWidth / w, maxHeight / h);
  }
  imgWidth.value = Math.floor(w * scale);
  imgHeight.value = Math.floor(h * scale);
};

// 【核心修改2】尺寸校准
const calibrateSize = () => {
  // #ifdef H5
  const wrapper = document.getElementById('finalCanvasWrapper');
  if (wrapper) {
    const rect = wrapper.getBoundingClientRect();
    if (rect.width > 0 && rect.height > 0) {
      // 计算比例
      scaleX.value = imgWidth.value / rect.width;
      scaleY.value = imgHeight.value / rect.height;
      
      console.log(`📏 校准: 物理${imgWidth.value}x${imgHeight.value} / 视觉${rect.width.toFixed(0)}x${rect.height.toFixed(0)}`);
      
      canvasReady.value = true;
      nextTick(() => { 
        // 强制写入 DOM 属性，防止浏览器默认行为
        const canvasDom = wrapper.querySelector('canvas');
        if (canvasDom) {
            canvasDom.width = imgWidth.value;
            canvasDom.height = imgHeight.value;
        }
        initCanvas(); 
      });
    } else {
      setTimeout(calibrateSize, 100);
    }
  }
  // #endif
};

const initCanvas = () => {
  ctx = uni.createCanvasContext('maskCanvas', instance);
  if (!ctx) return;
  ctx.setLineCap('round');
  ctx.setLineJoin('round');
  ctx.setLineWidth(lineWidth.value); 
  ctx.setStrokeStyle('rgba(255, 255, 255, 0.8)'); 
};

// 【核心修改3】坐标计算
const getPoint = (e) => {
  // #ifdef H5
  // 优先使用 offsetX，最准
  if (e.offsetX !== undefined) {
      return { x: e.offsetX * scaleX.value, y: e.offsetY * scaleY.value };
  }
  
  const wrapper = document.getElementById('finalCanvasWrapper');
  if (!wrapper) return { x: 0, y: 0 };
  const rect = wrapper.getBoundingClientRect();
  
  let clientX = e.clientX;
  let clientY = e.clientY;

  if (e.touches && e.touches.length > 0) {
    clientX = e.touches[0].clientX;
    clientY = e.touches[0].clientY;
  }

  // 补救措施：如果 e.offsetX 不可用，用 rect 计算
  const x = (clientX - rect.left) * scaleX.value;
  const y = (clientY - rect.top) * scaleY.value;
  return { x, y };
  // #endif
};

// ================= 事件处理 (解决滑出边界问题) =================

// PC/H5 鼠标移动监听 (绑定到 window 确保滑出画布也能画)
// #ifdef H5
const windowMouseMove = (e) => {
  if (!isDrawing.value) return;
  const { x, y } = getPoint(e);
  console.log(x,y,"xxxx");
  handleDrawMove(x, y);
};
const windowMouseUp = () => {
  if (isDrawing.value) handleEnd();
};
// #endif

const handleStart = (e) => {
  if (!ctx) return;
  isDrawing.value = true;
  const { x, y } = getPoint(e);
  currentPath = [{ x, y }];
  ctx.moveTo(x, y);
  ctx.beginPath();
  
  ctx.setLineWidth(lineWidth.value * scaleX.value); // 适应缩放
  ctx.setStrokeStyle('rgba(255, 255, 255, 0.8)'); 
  ctx.setLineCap('round');
  ctx.setLineJoin('round');
  
  ctx.lineTo(x, y);
  ctx.stroke();
  ctx.draw(true);

  // #ifdef H5
  // 开始画时，监听全局移动，解决滑出边界失效问题
  window.addEventListener('mousemove', windowMouseMove);
  window.addEventListener('mouseup', windowMouseUp);
  // #endif
};

// 这里的 handleMove主要给 touch 使用
const handleMove = (e) => {
  if (!isDrawing.value || !ctx) return;
  if (e.preventDefault) e.preventDefault();
  const { x, y } = getPoint(e);
  handleDrawMove(x, y);
};

// 抽离绘图逻辑
const handleDrawMove = (x, y) => {
  currentPath.push({ x, y });
  ctx.lineTo(x, y);
  ctx.stroke();
  ctx.draw(true);
};

const handleEnd = () => {
  if (isDrawing.value) {
    isDrawing.value = false;
    if (drawHistory.value) drawHistory.value.push({ width: lineWidth.value * scaleX.value, points: [...currentPath] });
    currentPath = [];
    
    // #ifdef H5
    window.removeEventListener('mousemove', windowMouseMove);
    window.removeEventListener('mouseup', windowMouseUp);
    // #endif
  }
};

// 清理监听
onUnmounted(() => {
    // #ifdef H5
    window.removeEventListener('mousemove', windowMouseMove);
    window.removeEventListener('mouseup', windowMouseUp);
    // #endif
});

const clearCanvas = () => {
  if (!ctx) return;
  // 清空范围要足够大，覆盖缩放误差
  ctx.clearRect(0, 0, imgWidth.value * 2, imgHeight.value * 2);
  ctx.draw();
  drawHistory.value = [];
};

const undo = () => {
  if (!drawHistory.value || drawHistory.value.length === 0) return;
  drawHistory.value.pop();
  ctx.clearRect(0, 0, imgWidth.value * 2, imgHeight.value * 2);
  ctx.draw(); 
  setTimeout(() => {
     drawHistory.value.forEach(pathObj => {
        ctx.beginPath();
        ctx.setLineWidth(pathObj.width); 
        ctx.setStrokeStyle('rgba(255, 255, 255, 0.8)');
        ctx.setLineCap('round');
        ctx.setLineJoin('round');
        const points = pathObj.points;
        if (points.length > 0) {
          ctx.moveTo(points[0].x, points[0].y);
          for (let i = 1; i < points.length; i++) {
             ctx.lineTo(points[i].x, points[i].y);
          }
          ctx.stroke();
        }
        ctx.draw(true); 
     });
  }, 10);
};

// ================= 提交与工具 =================
const submitProcess = () => {
  loading.value = true;
  startFakeProgress();
  setTimeout(() => {
      uni.canvasToTempFilePath({
        canvasId: 'maskCanvas',
        fileType: 'png',
        width: imgWidth.value,
        height: imgHeight.value,
        destWidth: imgWidth.value, 
        destHeight: imgHeight.value,
        success: (res) => {
          uploadFiles(originalImage.value, res.tempFilePath);
        },
        fail: (err) => {
           console.error("生成失败", err);
           loading.value = false;
           stopFakeProgress();
           uni.showToast({ title: '生成蒙版失败', icon: 'none'});
        }
      }, instance);
  }, 200);
};

const uploadFiles = async (imagePath, maskPath) => {
  // #ifdef H5
  try {
    const formData = new FormData();
    const imageBlob = await urlToBlob(imagePath);
    const maskBlob = await urlToBlob(maskPath);
    if (maskBlob.size < 100) throw new Error("蒙版数据异常");
    formData.append('image', imageBlob, 'image.png');
    formData.append('mask', maskBlob, 'mask.png');
    const response = await fetch(API_URL, { method: 'POST', body: formData });
    if (!response.ok) throw new Error('Server Error');
    const resultBlob = await response.blob();
    if (resultBlob.size === 0) throw new Error('返回空图');
    const resultUrl = URL.createObjectURL(resultBlob);
    progress.value = 100; loadingTitle.value = "处理完成！"; stopFakeProgress();
    setTimeout(() => { handleSuccess(resultUrl); }, 500);
  } catch (error) {
    console.error(error); loading.value = false; stopFakeProgress();
    uni.showToast({ title: '处理失败', icon: 'none' });
  }
  // #endif
  // #ifndef H5
  uni.showToast({ title: '请在 H5 环境下测试', icon: 'none' });
  loading.value = false; stopFakeProgress();
  // #endif
};

const urlToBlob = (url) => {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('GET', url, true); xhr.responseType = 'blob';
    xhr.onload = () => { if (xhr.status === 200) resolve(xhr.response); else reject(new Error('转换失败')); };
    xhr.onerror = reject; xhr.send();
  });
};

const handleSuccess = (url) => {
  const img = new Image();
  img.onload = () => {
      processedImage.value = url;
      loading.value = false;
      step.value = 'result';
      sliderPosition.value = 100;
      setTimeout(() => {
        let pos = 100;
        const timer = setInterval(() => {
          pos -= 2; sliderPosition.value = pos;
          if(pos <= 50) clearInterval(timer);
        }, 10);
      }, 500);
  };
  img.src = url;
};

// 滑块逻辑
const handleSliderStart = () => { isSliderDragging.value = true; };
const handleSliderEnd = () => { isSliderDragging.value = false; };
const handleSliderMove = (e) => {
  if (e.type === 'mousemove' && !isSliderDragging.value) return;
  const sysInfo = uni.getSystemInfoSync();
  let clientX = e.touches && e.touches.length > 0 ? e.touches[0].clientX : e.clientX;
  let rectLeft = (sysInfo.windowWidth - imgWidth.value) / 2;
  let percent = ((clientX - rectLeft) / imgWidth.value) * 100;
  if(percent < 0) percent = 0; if(percent > 100) percent = 100;
  sliderPosition.value = percent;
};

const reset = () => {
  step.value = 'upload'; processedImage.value = ''; originalImage.value = '';
  isDrawing.value = false; progress.value = 0; drawHistory.value = []; 
  canvasReady.value = false; 
};

const saveImage = () => {
  // #ifdef H5
  const link = document.createElement('a');
  link.href = processedImage.value; link.download = `removed_${Date.now()}.png`; link.click();
  // #endif
};
</script>

<style lang="scss">
.container {
  min-height: 100vh; background: #f8f9fa; padding: 30rpx;
  display: flex; flex-direction: column; align-items: center;
}
.header {
  margin: 40rpx 0; text-align: center;
  .title { font-size: 40rpx; font-weight: bold; color: #333; display: block; }
  .subtitle { font-size: 26rpx; color: #888; margin-top: 10rpx; display: block; }
}

/* 1. 上传区 */
.upload-zone {
  width: 100%; height: 500rpx; background: #fff; border-radius: 24rpx; border: 4rpx dashed #ddd;
  display: flex; flex-direction: column; align-items: center; justify-content: center; cursor: pointer;
  .upload-icon { width: 100rpx; height: 100rpx; margin-bottom: 20rpx; }
  .upload-text { font-size: 32rpx; color: #333; font-weight: 500; }
  .upload-sub { font-size: 24rpx; color: #aaa; margin-top: 10rpx; }
}

/* 2. 涂抹区 */
.paint-zone {
  display: flex; flex-direction: column; align-items: center;

  .canvas-wrapper {
    position: relative;
    box-shadow: 0 10rpx 30rpx rgba(0, 0, 0, 0.1);
    border-radius: 12rpx;
    overflow: hidden;
    background: #000;
    
    .bg-img { position: absolute; top: 0; left: 0; z-index: 1; }
    
    .mask-canvas {
      position: absolute; top: 0; left: 0; z-index: 10;
      background: rgba(0, 0, 0, 0.4); cursor: crosshair;
      touch-action: none; 
    }
  }

  .paint-tools {
    width: 100%; margin-top: 30rpx;
    .tool-info { text-align: center; color: #666; font-size: 28rpx; margin-bottom: 20rpx; }
    .slider-box { margin-bottom: 20rpx; padding: 0 20rpx; .label { font-size: 26rpx; color: #666; } }
    .tool-btns {
      display: flex; gap: 20rpx;
      .btn {
        border-radius: 50rpx; font-size: 30rpx; cursor: pointer;
        &.mini { width: 200rpx; background: #fff; color: #333; border: 1px solid #ddd; }
        &.primary { flex: 1; background: #007aff; color: #fff; }
      }
    }
  }
}

/* 3. 结果对比区 */
.compare-zone {
  display: flex; flex-direction: column; align-items: center;
  .compare-container {
    position: relative; border-radius: 12rpx; overflow: hidden;
    box-shadow: 0 10rpx 30rpx rgba(0, 0, 0, 0.15); cursor: ew-resize;
  }
  .full-size { width: 100%; height: 100%; display: block; }
  .result-img { position: absolute; top: 0; left: 0; z-index: 1; }
  .top-img-wrapper {
    position: absolute; top: 0; left: 0; height: 100%; z-index: 2; overflow: hidden;
    border-right: 2px solid #fff; background: #fff;
  }
  .slider-bar {
    position: absolute; top: 0; bottom: 0; width: 40rpx; transform: translateX(-50%);
    z-index: 10; display: flex; align-items: center; justify-content: center;
    .slider-btn {
      width: 60rpx; height: 60rpx; background: #fff; border-radius: 50%;
      box-shadow: 0 4rpx 10rpx rgba(0, 0, 0, 0.3); text-align: center; line-height: 60rpx;
      color: #333; font-weight: bold;
    }
  }
  .label {
    position: absolute; bottom: 20rpx; padding: 4rpx 12rpx; background: rgba(0, 0, 0, 0.6);
    color: #fff; font-size: 22rpx; border-radius: 8rpx;
  }
  .original-label { left: 20rpx; }
  .result-label { right: 20rpx; z-index: 1; }
  .action-area {
    margin-top: 40rpx; width: 100%; display: flex; gap: 30rpx;
    .btn { flex: 1; border-radius: 50rpx; cursor: pointer; }
    .secondary { background: #fff; border: 1px solid #ddd; }
    .primary { background: #007aff; color: #fff; }
  }
}

/* 4. Loading */
.loading-mask {
  position: fixed; top: 0; left: 0; right: 0; bottom: 0;
  background: rgba(255, 255, 255, 0.95); z-index: 999;
  display: flex; flex-direction: column; align-items: center; justify-content: center;
  .progress-box { width: 80%; max-width: 600rpx; display: flex; flex-direction: column; align-items: center; }
  .loading-title { font-size: 34rpx; font-weight: bold; color: #333; margin-bottom: 30rpx; }
  .progress-bar-bg { width: 100%; height: 16rpx; background: #eee; border-radius: 10rpx; overflow: hidden; margin-bottom: 20rpx; }
  .progress-bar-fill { height: 100%; background: linear-gradient(90deg, #007aff, #00c6ff); border-radius: 10rpx; transition: width 0.1s linear; }
  .progress-num { font-size: 40rpx; font-weight: bold; color: #007aff; }
  .loading-tip { margin-top: 20rpx; font-size: 24rpx; color: #999; }
}
</style>