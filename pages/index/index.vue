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
				<image :src="originalImage" class="bg-img"
					:style="{ width: imgWidth + 'px', height: imgHeight + 'px' }" />

				<canvas canvas-id="maskCanvas" id="maskCanvas" class="mask-canvas"
					:style="{ width: imgWidth + 'px', height: imgHeight + 'px' }" :width="imgWidth" :height="imgHeight"
					@touchstart="handleStart" @touchmove="handleMove" @touchend="handleEnd" @mousedown="handleStart"
					@mousemove="handleMove" @mouseup="handleEnd" @mouseleave="handleEnd" disable-scroll="true"></canvas>
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
// 1. 【引入】getCurrentInstance
import { ref, nextTick, getCurrentInstance } from 'vue';

// 2. 【关键】获取当前组件实例 (必须写在所有函数外面！)
const instance = getCurrentInstance();

// ================= 配置区 =================
const BASE_URL = 'http://111.231.120.121:3001'; 
const API_URL = `${BASE_URL}/api/remove-watermark`;

// ================= 状态变量 =================
const step = ref('upload'); 
const originalImage = ref('');
const processedImage = ref('');
const loading = ref(false);

const imgWidth = ref(300);
const imgHeight = ref(300);
let ctx = null;

const isDrawing = ref(false); 
const isSliderDragging = ref(false);
const sliderPosition = ref(50);

// 进度条相关
const progress = ref(0);
const loadingTitle = ref('正在上传...');
let progressTimer = null;

// ================= 进度条逻辑 =================
const startFakeProgress = () => {
  progress.value = 0;
  loadingTitle.value = '正在上传图片...';
  if (progressTimer) clearInterval(progressTimer);

  progressTimer = setInterval(() => {
    if (progress.value < 30) {
      progress.value += 2;
    } else if (progress.value < 80) {
      progress.value += 0.5;
      loadingTitle.value = 'AI 正在智能识别水印...';
    } else if (progress.value < 99) {
      progress.value += 0.1;
      loadingTitle.value = '正在进行深度重绘...';
    }
  }, 50);
};

const stopFakeProgress = () => {
  if (progressTimer) clearInterval(progressTimer);
  // 如果是错误停止，不设为100；如果是成功，外部会设为100
};

// ================= 1. 图片选择 =================
const chooseImage = () => {
  uni.chooseImage({
    count: 1,
    sizeType: ['compressed'],
    success: (res) => {
      const filePath = res.tempFilePaths[0];
      originalImage.value = filePath;
      
      uni.getImageInfo({
        src: filePath,
        success: (image) => {
          calculateCanvasSize(image.width, image.height);
          step.value = 'paint';
          
          setTimeout(() => {
            initCanvas();
          }, 200);
        }
      });
    }
  });
};

const calculateCanvasSize = (w, h) => {
  const sysInfo = uni.getSystemInfoSync();
  const maxWidth = sysInfo.windowWidth - 40; 
  const maxHeight = sysInfo.windowHeight * 0.6; 
  
  let scale = 1;
  if (w > maxWidth || h > maxHeight) {
    scale = Math.min(maxWidth / w, maxHeight / h);
  }
  
  imgWidth.value = w * scale;
  imgHeight.value = h * scale;
};

// ================= 2. 画布逻辑 =================
const initCanvas = () => {
  // 【关键修改】传入 instance，否则找不到 canvas
  ctx = uni.createCanvasContext('maskCanvas', instance);
  
  if (!ctx) {
    console.error("❌ 画布上下文创建失败");
    return;
  }
  
  ctx.setLineCap('round');
  ctx.setLineJoin('round');
  ctx.setLineWidth(20); 
  ctx.setStrokeStyle('rgba(255, 255, 255, 0.8)'); 
};

const getPoint = (e) => {
  let x = 0, y = 0;
  if (e.touches && e.touches.length > 0) {
    x = e.touches[0].x;
    y = e.touches[0].y;
  } else {
    if (e.offsetX !== undefined) {
       x = e.offsetX;
       y = e.offsetY;
    } else if (e.clientX !== undefined) {
       x = e.clientX; 
       y = e.clientY; 
    }
  }
  return { x, y };
};

const handleStart = (e) => {
  if (!ctx) return;
  isDrawing.value = true;
  const { x, y } = getPoint(e);
  ctx.moveTo(x, y);
  ctx.beginPath(); 
};

const handleMove = (e) => {
  if (!ctx || !isDrawing.value) return;
  if (e.preventDefault) e.preventDefault();
  const { x, y } = getPoint(e);
  ctx.lineTo(x, y);
  ctx.stroke();
  ctx.draw(true); 
};

const handleEnd = () => {
  isDrawing.value = false;
};

const clearCanvas = () => {
  if (!ctx) return;
  ctx.clearRect(0, 0, imgWidth.value, imgHeight.value);
  ctx.draw();
};

// ================= 3. 提交与处理 =================
const submitProcess = () => {
  loading.value = true;
  startFakeProgress(); // 启动进度条

  // 延时确保渲染
  setTimeout(() => {
      uni.canvasToTempFilePath({
        canvasId: 'maskCanvas',
        fileType: 'png',
        width: imgWidth.value,
        height: imgHeight.value,
        destWidth: imgWidth.value, 
        destHeight: imgHeight.value,
        success: (res) => {
          const maskPath = res.tempFilePath;
          console.log("蒙版生成成功:", maskPath);
          uploadFiles(originalImage.value, maskPath);
        },
        fail: (err) => {
          console.error("蒙版生成失败:", err);
          loading.value = false;
          stopFakeProgress(); // 【关键】失败要停止进度条
          uni.showToast({ title: '生成蒙版失败', icon: 'none' });
        }
      }, instance); // 【关键】这里必须传入 instance！
  }, 200);
};

const uploadFiles = async (imagePath, maskPath) => {
  // #ifdef H5
  try {
    const formData = new FormData();
    const imageBlob = await urlToBlob(imagePath);
    const maskBlob = await urlToBlob(maskPath);
    
    // 【关键】检查文件大小，防止传空文件导致后端 500
    console.log("原图大小:", imageBlob.size, "蒙版大小:", maskBlob.size);
    if (maskBlob.size < 100) throw new Error("蒙版数据异常(为空)");

    formData.append('image', imageBlob, 'image.png');
    formData.append('mask', maskBlob, 'mask.png');

    const response = await fetch(API_URL, {
      method: 'POST',
      body: formData
    });

    if (!response.ok) throw new Error('Server Error');

    const resultBlob = await response.blob();
    if (resultBlob.size === 0) throw new Error('返回的图片为空');
    
    const resultUrl = URL.createObjectURL(resultBlob);
    
    // 成功！跑满进度条
    progress.value = 100;
    loadingTitle.value = "处理完成！";
    stopFakeProgress();

    setTimeout(() => {
        handleSuccess(resultUrl);
    }, 500);

  } catch (error) {
    console.error(error);
    loading.value = false;
    stopFakeProgress(); // 【关键】出错要停止
    uni.showToast({ title: '处理失败，请重试', icon: 'none' });
  }
  // #endif

  // #ifndef H5
  uni.showToast({ title: '演示仅支持 H5', icon: 'none' });
  loading.value = false;
  stopFakeProgress();
  // #endif
};

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
  const img = new Image();
  img.onload = () => {
      processedImage.value = url;
      loading.value = false;
      step.value = 'result';
      sliderPosition.value = 100;
      
      setTimeout(() => {
        let pos = 100;
        const timer = setInterval(() => {
          pos -= 2;
          sliderPosition.value = pos;
          if(pos <= 50) clearInterval(timer);
        }, 10);
      }, 500);
  };
  img.src = url;
};

// ================= 4. 结果页滑块 =================
const handleSliderStart = () => { isSliderDragging.value = true; };
const handleSliderEnd = () => { isSliderDragging.value = false; };
const handleSliderMove = (e) => {
  if (e.type === 'mousemove' && !isSliderDragging.value) return;
  const sysInfo = uni.getSystemInfoSync();
  
  let clientX;
  if (e.touches && e.touches.length > 0) clientX = e.touches[0].clientX;
  else clientX = e.clientX;

  let rectLeft = (sysInfo.windowWidth - imgWidth.value) / 2;
  let percent = ((clientX - rectLeft) / imgWidth.value) * 100;
  if(percent < 0) percent = 0;
  if(percent > 100) percent = 100;
  sliderPosition.value = percent;
};

const reset = () => {
  step.value = 'upload';
  processedImage.value = '';
  originalImage.value = '';
  isDrawing.value = false;
  progress.value = 0;
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

		.title {
			font-size: 40rpx;
			font-weight: bold;
			color: #333;
			display: block;
		}

		.subtitle {
			font-size: 26rpx;
			color: #888;
			margin-top: 10rpx;
			display: block;
		}
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
		cursor: pointer;
		/* 鼠标变为手型 */

		.upload-icon {
			width: 100rpx;
			height: 100rpx;
			margin-bottom: 20rpx;
		}

		.upload-text {
			font-size: 32rpx;
			color: #333;
			font-weight: 500;
		}

		.upload-sub {
			font-size: 24rpx;
			color: #aaa;
			margin-top: 10rpx;
		}
	}

	/* 2. 涂抹区 */
	.paint-zone {
		display: flex;
		flex-direction: column;
		align-items: center;

		.canvas-wrapper {
			position: relative;
			box-shadow: 0 10rpx 30rpx rgba(0, 0, 0, 0.1);
			border-radius: 12rpx;
			overflow: hidden;
			background: #000;
		}

		.bg-img {
			position: absolute;
			top: 0;
			left: 0;
			z-index: 1;
		}

		.mask-canvas {
			position: absolute;
			top: 0;
			left: 0;
			z-index: 10;
			background: rgba(0, 0, 0, 0.4);
			cursor: crosshair;
			/* 鼠标变为十字准星 */
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
					cursor: pointer;

					&.mini {
						width: 200rpx;
						background: #fff;
						color: #333;
						border: 1px solid #ddd;
					}

					&.primary {
						flex: 1;
						background: #007aff;
						color: #fff;
					}
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
			box-shadow: 0 10rpx 30rpx rgba(0, 0, 0, 0.15);
			cursor: ew-resize;
			/* 鼠标变为左右箭头 */
		}

		.full-size {
			width: 100%;
			height: 100%;
			display: block;
		}

		.result-img {
			position: absolute;
			top: 0;
			left: 0;
			z-index: 1;
		}

		.top-img-wrapper {
			position: absolute;
			top: 0;
			left: 0;
			height: 100%;
			z-index: 2;
			overflow: hidden;
			border-right: 2px solid #fff;
			background: #fff;
		}

		.slider-bar {
			position: absolute;
			top: 0;
			bottom: 0;
			width: 40rpx;
			transform: translateX(-50%);
			z-index: 10;
			display: flex;
			align-items: center;
			justify-content: center;

			.slider-btn {
				width: 60rpx;
				height: 60rpx;
				background: #fff;
				border-radius: 50%;
				box-shadow: 0 4rpx 10rpx rgba(0, 0, 0, 0.3);
				text-align: center;
				line-height: 60rpx;
				color: #333;
				font-weight: bold;
			}
		}

		.label {
			position: absolute;
			bottom: 20rpx;
			padding: 4rpx 12rpx;
			background: rgba(0, 0, 0, 0.6);
			color: #fff;
			font-size: 22rpx;
			border-radius: 8rpx;
		}

		.original-label {
			left: 20rpx;
		}

		.result-label {
			right: 20rpx;
			z-index: 1;
		}

		.action-area {
			margin-top: 40rpx;
			width: 100%;
			display: flex;
			gap: 30rpx;

			.btn {
				flex: 1;
				border-radius: 50rpx;
				cursor: pointer;
			}

			.secondary {
				background: #fff;
				border: 1px solid #ddd;
			}

			.primary {
				background: #007aff;
				color: #fff;
			}
		}
	}

	/* Loading 蒙层 */
	/* Loading 蒙层 & 进度条样式 */
	.loading-mask {
	  position: fixed;
	  top: 0; left: 0; right: 0; bottom: 0;
	  background: rgba(255, 255, 255, 0.95); /* 背景稍微不透明一点，遮住后面 */
	  z-index: 999;
	  display: flex;
	  flex-direction: column;
	  align-items: center;
	  justify-content: center;
	  
	  .progress-box {
	    width: 80%;
	    max-width: 600rpx;
	    display: flex;
	    flex-direction: column;
	    align-items: center;
	  }
	
	  .loading-title {
	    font-size: 34rpx;
	    font-weight: bold;
	    color: #333;
	    margin-bottom: 30rpx;
	  }
	
	  .progress-bar-bg {
	    width: 100%;
	    height: 16rpx;
	    background: #eee;
	    border-radius: 10rpx;
	    overflow: hidden;
	    margin-bottom: 20rpx;
	  }
	
	  .progress-bar-fill {
	    height: 100%;
	    background: linear-gradient(90deg, #007aff, #00c6ff); /* 渐变色更好看 */
	    border-radius: 10rpx;
	    transition: width 0.1s linear; /* 丝滑过渡 */
	  }
	
	  .progress-num {
	    font-size: 40rpx;
	    font-weight: bold;
	    color: #007aff;
	    font-family: Arial, Helvetica, sans-serif;
	  }
	
	  .loading-tip {
	    margin-top: 20rpx;
	    font-size: 24rpx;
	    color: #999;
	  }
	}

	@keyframes spin {
		100% {
			transform: rotate(360deg);
		}
	}
</style>
