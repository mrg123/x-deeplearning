/*
 * Copyright 1999-2017 Alibaba Group.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
*/

#include "xdl/core/ops/take_op.h"
#include "xdl/core/framework/op_registry.h"
#include "xdl/core/lib/common_defines.h"
#include "xdl/core/framework/gpu/gpu_device.h"

namespace xdl {
namespace {

template <typename T, typename I>
__global__ void TakeOpKernel(const T* in,
                             const I* indicator,
                             size_t row,
                             size_t col,
                             T* out) {
  size_t id_num = row * col;
  CUDA_KERNEL_LOOP(k, id_num) {
    size_t i = k / col;
    size_t j = k % col;
    I rrow = indicator[i];
    out[k] = in[rrow * col + j];
  }
}

}  // namespace

template <typename T, typename I>
class TakeGpuOp : public GpuOpKernel {
 public:
  Status Init(OpKernelConstruction* ctx) override {
    return Status::Ok();
  }
  Status LaunchKernel(OpKernelContext* ctx, CudaStream* stream) override;
};

template <typename T, typename I>
Status TakeGpuOp<T, I>::LaunchKernel(OpKernelContext* ctx, CudaStream* stream) {
  Tensor feature, indicator, output;
  XDL_CHECK_STATUS(ctx->GetInput(0, &feature));
  XDL_CHECK_STATUS(ctx->GetInput(1, &indicator));
  XDL_CHECK_COND(1 == indicator.Shape().Size(),
                 Status::ArgumentError("indicator must be rank 1 tensor"));

  auto fea_dims = feature.Shape().Dims();
  std::vector<size_t> dims(fea_dims.begin(), fea_dims.end());
  dims[0] = indicator.Shape().NumElements();
  TensorShape out_shape(dims);
  XDL_CHECK_STATUS(ctx->AllocateOutput(0, out_shape, &output));

  size_t row = dims[0];
  size_t col = feature.Shape().NumElements() / feature.Shape()[0];
  T* pin = feature.Raw<T>(), *pout = output.Raw<T>();
  I* pind = indicator.Raw<I>();

  cudaStream_t st = stream->GetInternal();
  CUDA_CHECK(cudaMemsetAsync(pout, 0, sizeof(T) * out_shape.NumElements(), st));
  TakeOpKernel<T, I><<<
      CUDA_GET_BLOCKS(row * col),
      CUDA_NUM_THREADS,
      0,
      st>>>(pin, pind, row, col, pout);
  return Status::Ok();
}

#define REGISTER_GPU_KERNEL(T, I)              \
  XDL_REGISTER_KERNEL(TakeOp, TakeGpuOp<T, I>) \
  .Device("GPU")                               \
  .AttrDataType<T>("dtype")                    \
  .AttrDataType<I>("itype")

REGISTER_GPU_KERNEL(float, int32_t);
REGISTER_GPU_KERNEL(float, int64_t);
REGISTER_GPU_KERNEL(double, int32_t);
REGISTER_GPU_KERNEL(double, int64_t);

#undef REGISTER_GPU_KERNEL

}  // namespace xdl
