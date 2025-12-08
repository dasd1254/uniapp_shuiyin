<template>
	<div class="container">
		<button @click="chooseImage" class="btn">选择图片并去除水印</button>

		<div v-if="originalImage" class="image-area">
			<text>原图：</text>
			<image :src="originalImage" mode="widthFix" class="img"></image>
		</div>

		<div v-if="processedImage" class="image-area">
			<text>结果：</text>
			<image :src="processedImage" mode="widthFix" class="img"></image>
			<button @click="saveImage" class="btn-save">保存到相册</button>
		</div>

		<div v-if="loading">处理中...</div>
	</div>
</template>

<script setup>
	import {
		ref
	} from 'vue';

	const originalImage = ref('');
	const processedImage = ref('');
	const loading = ref(false);

	// 请替换为你的服务器真实IP或域名
	// 注意：微信小程序要求使用 HTTPS 域名，开发调试阶段需在详情里勾选“不校验合法域名”
const API_URL = '/api/remove-watermark';
const BASE_URL = 'http://111.231.120.121:3000'; // 用于拼接图片地址

	const chooseImage = () => {
		uni.chooseImage({
			count: 1,
			success: (res) => {
				originalImage.value = res.tempFilePaths[0];
				uploadAndProcess(res.tempFilePaths[0]);
			}
		});
	};

const uploadAndProcess = (filePath) => {
  loading.value = true;
  uni.uploadFile({
    url: API_URL, 
    filePath: filePath,
    name: 'file', 
    success: (uploadFileRes) => {
      // 1. Node.js 返回的是字符串，需要 parse 一下
      const res = JSON.parse(uploadFileRes.data);
      
      if(res.code === 200) {
          // 2. 拼接完整的图片路径
          processedImage.value = BASE_URL + res.data.url;
          loading.value = false;
      } else {
          uni.showToast({title: '处理失败', icon: 'none'});
          loading.value = false;
      }
    },
    fail: (err) => {
        console.error("上传失败", err);
        loading.value = false;
    }
  });
};

	const saveImage = () => {
		uni.saveImageToPhotosAlbum({
			filePath: processedImage.value,
			success: () => uni.showToast({
				title: '保存成功'
			})
		})
	}
</script>

<style>
	.container {
		padding: 20px;
		display: flex;
		flex-direction: column;
		align-items: center;
	}

	.img {
		width: 100%;
		margin-top: 10px;
		border-radius: 8px;
	}

	.btn {
		background-color: #007aff;
		color: white;
		padding: 10px 20px;
		border-radius: 20px;
	}

	.btn-save {
		background-color: #4cd964;
		color: white;
		margin-top: 10px;
	}

	.image-area {
		margin-top: 20px;
		width: 100%;
		text-align: center;
	}
</style>
