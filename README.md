# AWS Practice Infrastructure

Repository học AWS Solutions Architect – Associate kết hợp với thực hành Infrastructure as Code bằng Terraform.

## Cấu trúc

- `textbook/`: Bài học và lab về IAM, networking, compute, data, serverless, CI/CD và capstone.
- `dev/lab/` và `prod/lab/`: Hạ tầng lab xuyên suốt các section, mỗi môi trường có Terraform state riêng.
- `dev/capstone/` và `prod/capstone/`: Môi trường capstone độc lập với lab, mỗi thư mục là một Terraform root module riêng.
- `.github/workflows/terraform.yml`: GitHub Actions kiểm tra định dạng và validate các Terraform root.

## Bắt đầu

Xem bài học và lab tương ứng trong `textbook/`. Trước khi triển khai Terraform, tạo `terraform.tfvars` cục bộ từ `terraform.tfvars.example` nếu có, cấu hình backend riêng cho đúng môi trường, rồi chạy `terraform init`, `terraform plan` và xem xét kỹ kế hoạch trước khi áp dụng.

Terraform state có thể chứa dữ liệu nhạy cảm. Bảo vệ state và thông tin xác thực; không commit credentials, secrets hoặc `terraform.tfvars`. Ước tính chi phí AWS trước khi triển khai và dọn dẹp tài nguyên lab khi không còn cần.
