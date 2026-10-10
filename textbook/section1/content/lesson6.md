# Section 1 — Bài 6: Kết nối riêng đến dịch vụ AWS bằng VPC endpoints

## Mục tiêu bài học

Sau bài này, người học có thể:

- Giải thích vì sao một workload trong private subnet có thể truy cập dịch vụ AWS mà không cần gửi traffic qua Internet Gateway hoặc NAT Gateway.
- Phân biệt gateway endpoint với interface endpoint (AWS PrivateLink) về cách hoạt động, phạm vi hỗ trợ, định tuyến, DNS, bảo mật và chi phí.
- Nhận biết dịch vụ AWS nào hỗ trợ gateway endpoint, và khi nào cần interface endpoint.
- Giải thích vai trò riêng biệt của route table, security group, endpoint policy, IAM identity policy và resource policy trong một request đến dịch vụ AWS.
- Đọc luồng kết nối S3 qua gateway endpoint, bao gồm route prefix list, DNS và endpoint policy; hiểu vì sao route đến endpoint không tự cấp quyền truy cập dữ liệu.
- Thiết kế truy cập tối thiểu cho workload private, chọn endpoint phù hợp và so sánh với NAT Gateway theo lượng traffic, loại dịch vụ và chi phí.
- Thêm S3 gateway endpoint vào networking module của `dev/lab/` bằng Terraform, giới hạn route table association và policy theo nhu cầu, review plan trước khi apply.
- Nhận diện giới hạn của VPC endpoint, gồm phạm vi Region, các đường truy cập không tự được endpoint bao phủ và các điểm cần kiểm tra khi troubleshooting.

## 1. Bối cảnh và vấn đề

Workload trong private subnet thường cần gọi dịch vụ AWS. Ví dụ, một EC2 instance cần tải object từ Amazon S3, một container cần lấy image từ Amazon ECR, hoặc một ứng dụng cần gọi AWS Systems Manager. Nếu không có kết nối riêng phù hợp, traffic có thể phải đi từ private subnet qua NAT Gateway rồi ra một public endpoint của dịch vụ.

Đường đi qua NAT có thể hoạt động, nhưng có các đánh đổi:

- Workload phụ thuộc vào NAT Gateway, route, Internet egress và public service endpoint.
- NAT Gateway có phí theo thời gian và dữ liệu xử lý; nhiều traffic nội bộ đến AWS service có thể làm tăng chi phí.
- Traffic đi qua một đường Internet egress có thể không phù hợp với yêu cầu giảm bề mặt phơi lộ hoặc kiểm soát đường truyền.
- Quản trị viên cần phân biệt traffic thực sự đến Internet với traffic chỉ đến dịch vụ AWS.

**VPC endpoint** cung cấp cách kết nối VPC đến một số dịch vụ AWS hoặc endpoint service được hỗ trợ mà không cần đi theo đường Internet thông thường. Endpoint có thể giúp workload ở private subnet truy cập dịch vụ đích qua hạ tầng mạng riêng của AWS, nhưng endpoint không tự cấp quyền IAM, không mã hóa mọi dữ liệu thay cho ứng dụng và không có nghĩa mọi traffic của workload đều bị cô lập khỏi Internet.

Ví dụ, một ứng dụng chỉ cần đọc object từ một bucket S3 cụ thể. Với S3 gateway endpoint, route table của private subnet được cấu hình để traffic đến dải địa chỉ dịch vụ S3 trong Region đi qua endpoint. Workload vẫn cần IAM permission phù hợp và bucket policy có thể tiếp tục giới hạn truy cập. Nếu ứng dụng cũng gọi một API công khai không có VPC endpoint phù hợp, traffic đó vẫn cần một đường đi khác như NAT Gateway hoặc proxy egress được thiết kế riêng.

## 2. Khái niệm và thành phần cốt lõi

### VPC endpoint

VPC endpoint là điểm kết nối trong VPC đến một dịch vụ AWS được hỗ trợ hoặc một dịch vụ do bên thứ ba công bố qua AWS PrivateLink. Tùy endpoint type, AWS tích hợp đường kết nối bằng route table hoặc bằng network interface có private IP trong subnet.

Endpoint không đồng nghĩa với một proxy ứng dụng. Ứng dụng vẫn gọi API hoặc hostname dịch vụ; endpoint thay đổi đường mạng tương ứng theo loại endpoint và cấu hình DNS/route. Endpoint cũng không tự chứng minh danh tính workload hoặc cho phép API action: IAM và resource policy vẫn được đánh giá.

### Gateway endpoint

Gateway endpoint hiện được sử dụng cho Amazon S3 và Amazon DynamoDB. Endpoint được liên kết với một hoặc nhiều route table trong cùng Region và VPC. Khi tạo association, AWS thêm các route dùng service prefix list làm destination và gateway endpoint làm target.

Đặc điểm chính:

- Không tạo endpoint network interface trong subnet.
- Không cần security group để gắn trực tiếp vào endpoint.
- Cần gắn endpoint với các route table mà workload cần dùng.
- Route table có route cụ thể hơn cho dải IP dịch vụ sẽ ưu tiên route default đến NAT Gateway theo longest-prefix match.
- Endpoint policy có thể giới hạn các action/resource được phép đi qua endpoint, nhưng không tự cấp IAM permission.
- Gateway endpoint có phạm vi VPC/Region; không thể dùng như một endpoint transit chung cho traffic từ VPC peering, Transit Gateway hoặc mạng on-premises theo cách một số người học thường suy luận.

Gateway endpoint không có phí endpoint theo giờ như interface endpoint, nhưng các dịch vụ đích, data transfer và các resource khác vẫn có thể tính phí theo bảng giá. Kiểm tra giá hiện hành theo Region và loại traffic.

### Interface endpoint và AWS PrivateLink

**Interface endpoint** sử dụng AWS PrivateLink để tạo một hoặc nhiều **elastic network interface (ENI)** trong subnet đã chọn. ENI có private IP trong VPC; security group được gắn vào endpoint ENI để kiểm soát traffic đến interface endpoint. DNS có thể được cấu hình để hostname dịch vụ phân giải về địa chỉ private của endpoint.

Đặc điểm chính:

- Hỗ trợ nhiều dịch vụ AWS và endpoint service của bên thứ ba hơn gateway endpoint; danh sách phụ thuộc dịch vụ và Region.
- Có thể được truy cập từ các subnet trong VPC thông qua định tuyến nội bộ, không nhất thiết chỉ từ subnet nơi ENI endpoint được đặt.
- Cần chọn subnet/AZ phù hợp; triển khai endpoint interface trên nhiều AZ có thể cải thiện khả năng sẵn sàng nhưng có thể tăng chi phí.
- Security group của endpoint ENI cần cho phép inbound từ workload trên protocol/port phù hợp, thường là TCP 443 đối với API HTTPS.
- Có phí theo thời gian cho mỗi AZ/endpoint ENI và phí theo dữ liệu theo bảng giá hiện hành; không nên tạo thử trên account có ngân sách hạn chế nếu chưa xác nhận.
- Private DNS cần được cấu hình đúng và phải xét các yêu cầu DNS/VPC; hostname có thể tiếp tục là hostname chuẩn của dịch vụ nhưng phân giải về private IP của endpoint.

Interface endpoint không có nghĩa traffic được phép bởi IAM. Security group endpoint chỉ kiểm soát network path đến ENI; authorization của API vẫn phụ thuộc IAM/resource policy và endpoint policy nếu có.

### So sánh gateway endpoint và interface endpoint

| Tiêu chí | Gateway endpoint | Interface endpoint |
|---|---|---|
| Cơ chế tích hợp | Route table trỏ service prefix list đến gateway endpoint | ENI với private IP trong subnet, dùng AWS PrivateLink |
| Dịch vụ điển hình | S3, DynamoDB | Nhiều AWS services và endpoint services được PrivateLink hỗ trợ |
| Security group trên endpoint | Không gắn SG vào gateway endpoint | Có SG gắn với endpoint ENI |
| Cấu hình mạng chính | Chọn route table cần liên kết | Chọn subnet/AZ, SG, DNS; client cần đường đến ENI |
| DNS | Thông thường dùng hostname dịch vụ; route prefix list chọn đường đi | Private DNS có thể phân giải hostname dịch vụ về endpoint private IP |
| Chi phí endpoint | Không có phí endpoint theo giờ như interface endpoint; vẫn kiểm tra phí dịch vụ/data transfer | Thường có phí theo giờ/AZ và data processing |
| Phạm vi truy cập | Route table trong VPC được liên kết; không phải endpoint transit chung | Interface endpoint cung cấp private connectivity theo phạm vi dịch vụ/endpoint service; xem đặc tính kết nối và DNS của service |
| Use case | Truy cập S3/DynamoDB từ VPC qua route riêng | Truy cập API/service hỗ trợ PrivateLink mà không cần public egress |

### Endpoint policy, IAM policy và resource policy

Một request đến dịch vụ qua endpoint có thể chịu nhiều lớp authorization. Cần phân biệt:

- **IAM identity policy:** Gắn với IAM user/role/session của principal; xác định action/resource principal được phép thực hiện.
- **Endpoint policy:** Policy gắn với VPC endpoint, giới hạn request nào có thể đi qua endpoint đến dịch vụ. Endpoint policy không thay identity policy và không tự cấp quyền cho principal.
- **Resource policy:** Policy gắn với resource đích, ví dụ S3 bucket policy; có thể giới hạn principal, source VPC endpoint, account hoặc điều kiện khác.
- **Service control policy (SCP), permission boundary, session policy:** Có thể áp dụng thêm giới hạn ở cấp tổ chức, role hoặc phiên.
- **Network controls:** Route, security group và NACL quyết định packet có đến endpoint/service path được hay không; chúng không thay authorization IAM.

Thông thường request chỉ thành công nếu có đường mạng, endpoint/service cho phép kết nối, principal được IAM cho phép và resource policy không từ chối. Explicit Deny ở một policy áp dụng có thể chặn request dù một policy khác có Allow. Endpoint policy là một giới hạn bổ sung, không phải cách thay IAM bằng một policy mạng.

Ví dụ endpoint policy giới hạn S3 gateway endpoint tới một bucket không có nghĩa mọi workload trong VPC được phép đọc bucket đó. Workload vẫn cần IAM permission tương ứng; bucket policy cũng có thể từ chối request.

### Service prefix list và route table

Với gateway endpoint, AWS cung cấp service prefix list đại diện các địa chỉ IP của dịch vụ trong Region. Route table được gắn endpoint sẽ nhận route đến prefix list này với target là endpoint. Route này cụ thể hơn default route `0.0.0.0/0` đến NAT Gateway nên traffic đến dải S3/DynamoDB tương ứng đi theo endpoint route.

Không nên hard-code danh sách IP dịch vụ vào route hoặc security rule: địa chỉ có thể thay đổi và AWS cung cấp prefix list để biểu diễn các dải đó. Security group có thể tham chiếu managed prefix list ở các tình huống được hỗ trợ, nhưng cần phân biệt cấu hình SG với route table association của gateway endpoint.

## 3. Cách hoạt động: workload private truy cập S3 qua gateway endpoint

```text
Ứng dụng trong private subnet
   │ gọi S3 API bằng hostname dịch vụ
   │ DNS phân giải hostname dịch vụ
   ▼
Route table của private subnet
   │ route đến S3 service prefix list → Gateway Endpoint
   ▼
S3 Gateway Endpoint
   │ Endpoint policy lọc request đi qua endpoint
   ▼
Amazon S3
   │ IAM identity policy và bucket policy được đánh giá
   ▼
Response quay lại workload
```

Các bước của luồng:

1. **Ứng dụng tạo request.** Workload gọi S3 API bằng SDK/HTTPS và hostname S3 phù hợp với Region, chẳng hạn hostname regional. Request được ký bằng credentials tạm thời của IAM role gắn với workload; không đặt access key tĩnh trong mã nguồn.
2. **DNS phân giải tên dịch vụ.** Với gateway endpoint, ứng dụng thường tiếp tục dùng hostname dịch vụ S3. Gateway endpoint không tạo ENI riêng để hostname phải phân giải đến một private endpoint IP như interface endpoint.
3. **Route table chọn endpoint route.** Subnet của workload dùng route table đã liên kết gateway endpoint. Destination IP thuộc service prefix list được route đến endpoint; traffic đích khác tiếp tục dùng route phù hợp khác, chẳng hạn NAT Gateway cho default route.
4. **Endpoint policy được áp dụng.** Policy endpoint có thể giới hạn principal, action hoặc resource được phép đi qua endpoint. Nếu policy không cho phép request, request bị chặn ở lớp endpoint.
5. **Dịch vụ đánh giá quyền truy cập.** S3 đánh giá quyền IAM và bucket/access point policy cùng các giới hạn áp dụng. Endpoint route không cấp quyền `s3:GetObject` hoặc `s3:ListBucket`.
6. **Response quay lại.** Response được trả về workload theo đường kết nối; security group stateful thường cho phép response thuộc kết nối đã được cho phép. NACL stateless vẫn cần rule phù hợp ở hai chiều.
7. **Traffic không thuộc dịch vụ endpoint không tự đi qua endpoint.** Nếu ứng dụng gọi một website công khai hoặc AWS service không được gateway endpoint hỗ trợ, route endpoint không áp dụng. Traffic sẽ cần route khác hoặc thất bại nếu không có đường đi.

### So sánh luồng qua NAT và endpoint

```text
Không có S3 gateway endpoint:
Private workload → private route table → NAT Gateway → IGW → S3 public endpoint

Có S3 gateway endpoint:
Private workload → route table + S3 prefix-list route → S3 gateway endpoint → S3
```

Đường đi thực tế còn phụ thuộc DNS, Region, endpoint association, policy và cách ứng dụng gọi service. Endpoint không buộc mọi request đến dịch vụ phải đi qua endpoint nếu route table của subnet không được liên kết hoặc client đi qua một VPC/đường mạng khác.

## 4. Tư duy kiến trúc, bảo mật, chi phí và đánh đổi

### Tính sẵn sàng và khả năng phục hồi

Gateway endpoint được quản lý bởi AWS và không cần người dùng đặt ENI vào từng AZ. Tuy nhiên, endpoint chỉ phục vụ route table được liên kết; nếu private subnet dùng một route table khác hoặc route association bị thiếu, workload ở subnet đó có thể vẫn đi qua NAT hoặc không truy cập được dịch vụ.

Interface endpoint tạo ENI trong subnet/AZ được chọn. Khi dịch vụ cần tính sẵn sàng qua nhiều AZ, xem xét triển khai endpoint ở các AZ cần thiết và hiểu DNS/health behavior của service. Một ENI ở một AZ có thể tạo phụ thuộc vào AZ đó hoặc phát sinh cross-AZ traffic tùy client/endpoint configuration; đánh giá tài liệu dịch vụ và thiết kế hiện hành thay vì giả định một interface endpoint tự động đa AZ.

VPC endpoint không phải backup, replication hay DR. Nó cung cấp đường truy cập mạng đến một service, không bảo đảm dữ liệu trong service được phục hồi hoặc workload tiếp tục chạy khi Region/service gặp sự cố. DR vẫn cần xem xét dữ liệu, ứng dụng, quota, endpoint ở Region đích, policy và DNS/configuration.

### Bảo mật

- Ưu tiên IAM role và credentials tạm thời cho workload; không nhúng access key trong image, user data hoặc Terraform.
- Endpoint policy chỉ cho phép principal/action/resource cần thiết. Bắt đầu từ nhu cầu cụ thể; policy quá chặt có thể làm hỏng workload, policy quá rộng làm giảm tác dụng của endpoint.
- Kết hợp endpoint policy với IAM least privilege và bucket/resource policy. Nếu dùng điều kiện như `aws:SourceVpce` trong bucket policy, phải tính đến mọi caller hợp lệ như console/admin, replication, logging, backup và các VPC/endpoint khác; nếu bỏ sót, có thể tự khóa truy cập.
- Với interface endpoint, security group của endpoint ENI chỉ nhận traffic từ workload/subnet/SG cần thiết trên port dịch vụ; không mở inbound rộng nếu không cần.
- Giữ TLS và kiểm tra chứng thư/hostname theo chuẩn SDK. Private connectivity không đồng nghĩa payload được bảo vệ nếu ứng dụng cấu hình TLS sai.
- DNS là một phần của security boundary: xác minh private DNS và DNS resolution không làm request đi đến endpoint ngoài dự kiến; tránh ghi đè hostname bằng cấu hình thủ công không cần thiết.
- Theo dõi CloudTrail/service logs và VPC Flow Logs khi phù hợp, nhưng xem xét chi phí, retention và quyền đọc log.
- Endpoint policy không ngăn workload dùng NAT hoặc một đường truy cập khác nếu workload có route egress tương ứng. Muốn buộc traffic đi theo endpoint, cần thiết kế route, firewall, DNS, resource policy và egress guardrail nhất quán.

### Chi phí

Chi phí khác nhau giữa các endpoint type và service:

- Gateway endpoint không có phí endpoint theo giờ như interface endpoint; dịch vụ đích, data transfer hoặc các đặc điểm sử dụng khác vẫn có thể phát sinh phí.
- Interface endpoint thường tính phí theo thời gian cho mỗi AZ/endpoint và theo dữ liệu xử lý. Nhiều service hoặc nhiều AZ có thể làm tổng chi phí tăng.
- NAT Gateway có thể vẫn cần cho các traffic Internet/API khác; thêm endpoint không tự loại bỏ phí NAT nếu route/traffic còn sử dụng NAT.
- VPC Flow Logs, CloudTrail data events, CloudWatch logs/metrics hoặc kiểm thử tạo traffic có thể có phí riêng.

Hãy so sánh theo workload thực tế:

```text
Tổng chi phí phương án NAT
  = NAT Gateway theo giờ
  + dữ liệu NAT xử lý
  + data transfer và các thành phần liên quan

Tổng chi phí endpoint
  = phí endpoint theo loại/AZ (nếu có)
  + dữ liệu endpoint xử lý (nếu áp dụng)
  + data transfer/service charges
```

Gateway endpoint S3/DynamoDB thường là lựa chọn cần đánh giá đầu tiên cho traffic đến hai dịch vụ đó, nhưng vẫn cần xem bảng giá hiện hành, lưu lượng, yêu cầu policy và đường đi. Không tạo interface endpoint chỉ để “thử cho biết” trên account có ngân sách hạn chế; kiểm tra giá theo Region trước.

### Lựa chọn kiến trúc và đánh đổi

- **S3/DynamoDB từ private subnet:** Đánh giá gateway endpoint để định tuyến traffic đến service qua endpoint thay vì NAT. Bảo đảm route table đúng và IAM/resource policy cho phép.
- **Các AWS API hỗ trợ PrivateLink:** Đánh giá interface endpoint khi muốn private connectivity và giảm phụ thuộc public egress. Cân nhắc phí mỗi AZ, SG endpoint ENI, DNS và phạm vi service.
- **API public không có endpoint phù hợp:** Có thể cần NAT/proxy egress. VPC endpoint không phải giải pháp tổng quát để truy cập mọi website trên Internet.
- **Nhiều endpoint cho nhiều service:** Giảm một số luồng NAT nhưng tăng chi phí, số lượng policy/DNS/SG cần vận hành và bề mặt cấu hình cần review.
- **Endpoint policy rộng:** Dễ triển khai ban đầu nhưng ít tác dụng như guardrail bổ sung. Nên giới hạn resource/action khi yêu cầu đã rõ và kiểm thử để tránh chặn ứng dụng hợp lệ.
- **Endpoint policy rất hẹp ngay từ đầu:** Tăng giới hạn truy cập nhưng có thể làm gián đoạn ứng dụng nếu thiếu bucket, action, principal hoặc Region/service path hợp lệ. Dùng plan/test và CloudTrail để xác minh.
- **Buộc S3 chỉ truy cập qua một endpoint:** Có thể dùng resource policy condition như `aws:SourceVpce`, nhưng cần inventory mọi caller và endpoint hợp lệ, nếu không có thể khóa access ngoài dự kiến. Thiết kế theo đúng boundary/account và có phương án break-glass được kiểm soát.

### Giới hạn và các đường mạng cần phân biệt

- VPC endpoint gắn với dịch vụ/Region/endpoint type cụ thể; endpoint ở một Region không mặc nhiên đại diện endpoint của cùng dịch vụ ở Region khác.
- Gateway endpoint route association áp dụng cho route table trong VPC đó; không coi gateway endpoint như một gateway transit dùng chung cho peered VPC, Transit Gateway hoặc on-premises.
- Interface endpoint có mô hình PrivateLink và ENI riêng; khả năng kết nối từ VPC khác hoặc mạng on-premises phụ thuộc cấu hình DNS, routing, service exposure và yêu cầu endpoint cụ thể.
- Một endpoint chỉ thay đổi đường mạng; IAM, resource authorization, TLS và cấu hình ứng dụng vẫn cần chính xác.
- Endpoint không tự chuyển mọi request đến AWS service sang đường riêng. Region/hostname, DNS, route table association, endpoint policy và cách SDK gọi API đều có thể ảnh hưởng.

## 5. Quan sát trên AWS Management Console

Chỉ xem cấu hình hiện có; không tạo endpoint trong Console nếu Terraform sẽ sở hữu resource.

1. **Xác nhận account và Region.** VPC endpoint và service endpoint phụ thuộc Region. Xác nhận đúng account/Region trước khi so sánh service name hoặc route.
2. **Mở VPC Endpoints.** Tìm **VPC** trong AWS Management Console, mở **Endpoints** hoặc **VPC endpoints**, lọc theo VPC ID.
3. **Đọc loại và trạng thái endpoint.** Với mỗi endpoint, ghi service name, endpoint type, VPC, trạng thái, subnet/AZ, security group (nếu là interface endpoint), route tables (nếu là gateway endpoint) và private DNS setting (nếu hiện diện).
4. **Nếu là gateway endpoint, xem route table.** Mở các route table đã gắn và kiểm tra route destination dạng AWS-managed prefix list cùng target gateway endpoint. Xác minh đúng subnet nào dùng route table đó.
5. **Nếu là interface endpoint, xem ENI/DNS/SG.** Đọc private IP/subnet/AZ, security group và private DNS. Không chỉnh DNS hoặc SG; liên hệ hostname của service với private resolution theo cấu hình.
6. **Đọc endpoint policy.** Xem policy JSON và phân biệt nó với IAM role policy và resource policy của dịch vụ đích. Xác định policy này cho phép qua endpoint những principal/action/resource nào.
7. **Liên hệ với NAT route.** Kiểm tra private subnet có NAT default route hay không. Một service-specific endpoint route có thể được ưu tiên hơn default route, nhưng các destination khác vẫn theo route phù hợp.
8. **Giữ thao tác chỉ đọc.** Không tạo/xóa endpoint, thay route association, sửa endpoint policy, private DNS hoặc SG. Interface endpoint có thể phát sinh phí ngay khi tồn tại.

Nếu VPC chưa có endpoint, dùng sơ đồ và Terraform plan mẫu trong bài để phân tích. Không tạo endpoint chỉ để hoàn thành phần quan sát.

## 6. Thực hành

> - **Mục tiêu:** Thêm S3 gateway endpoint vào route table private hiện có trong networking module dùng chung và giới hạn endpoint policy cho bucket được chỉ định; hiểu được route/authorization được kiểm tra như thế nào.
> - **Môi trường:** Chỉ dùng `dev/lab/` của lab xuyên Sections 1–5. Không tạo state/root module riêng và không thay đổi `prod/lab/`.
> - **Chi phí dự kiến:** Gateway endpoint không có phí theo giờ như interface endpoint, nhưng S3, data transfer, NAT, logging hoặc traffic test vẫn có thể tính phí. Kiểm tra bảng giá theo Region.
> - **Rủi ro và phạm vi:** Endpoint thêm route cho các route table được chọn và endpoint policy có thể chặn request S3. Không thay bucket policy đang dùng chung, không áp điều kiện `aws:SourceVpce` trên bucket hiện hữu trong bài này, không tạo interface endpoint và không chạy `terraform destroy` cho lab dùng chung.

### Kiến trúc lab

Tái sử dụng VPC, private subnet và private route table đã được thiết kế ở các bài trước. Thêm S3 gateway endpoint vào đúng private route table để traffic S3 từ private subnet dùng route service prefix list. Các endpoint route khác hoặc default route NAT, nếu tồn tại, vẫn phục vụ traffic tương ứng khác.

```text
Application trong private subnet
          │ AWS SDK + IAM role
          ▼
Private route table
  ├── S3 prefix list → S3 Gateway Endpoint → Amazon S3
  └── 0.0.0.0/0     → NAT Gateway (nếu lab có cấu hình)
```

Bài không tạo bucket hoặc workload mới. Nếu chưa có bucket thử nghiệm do người học sở hữu và được phép dùng, chỉ validate/plan và review policy; không trỏ policy vào bucket của người khác hoặc dữ liệu production.

### Điều kiện trước khi bắt đầu

- Các bài trước đã tạo hoặc định nghĩa đúng VPC và private route table trong cùng Terraform state `dev/lab/`; nếu chưa có, dừng ở thiết kế/plan, không dựng thêm VPC.
- Đã xác định Region và service name S3 đúng partition/Region, thường theo dạng `com.amazonaws.<region>.s3`; xác nhận service hỗ trợ endpoint trong Region đó.
- Đã xác định bucket ARN thử nghiệm thuộc account/người học và các hành động cần thiết. Ví dụ dưới đây là read-only (`ListBucket`, `GetObject`); không dùng cho ứng dụng cần ghi object nếu chưa bổ sung action có chủ đích.
- Đã xác nhận AWS role/workload và Terraform state có quyền phù hợp; không dùng access key tĩnh trong `tfvars`.
- Tất cả thay đổi route table và endpoint policy được review. Endpoint policy quá chặt có thể làm request thất bại dù IAM policy cho phép.
- Không chạy `terraform apply` khi chưa xác nhận phạm vi, bucket sở hữu và chi phí/traffic.

### Các bước thực hiện

1. **Kiểm tra module và state.** Mở `dev/lab/main.tf` và `dev/lab/modules/networking/`. Xác định VPC resource/output, private route table resource ID, route table associations, Region provider và các endpoint đã có trong Terraform state. Nếu module networking chưa quản lý route table, truyền ID từ module sở hữu thay vì khai báo route table trùng.

2. **Chọn route table cần liên kết.** Với lab dùng một private route table chung, liên kết endpoint với route table đó. Nếu mỗi AZ có private route table riêng, liên kết tất cả route table cần truy cập S3. Không tự liên kết public route table hoặc route table của workload không thuộc phạm vi. Với S3 gateway endpoint, AWS thêm route service prefix list vào các route table đã chọn.

3. **Khai báo biến cấu hình.** Trong module networking, khai báo Region và danh sách bucket ARN được phép dùng endpoint, hoặc truyền Region từ root/provider theo convention hiện có. Ví dụ:

   ```hcl
   variable "aws_region" {
     description = "AWS Region dùng cho VPC và S3 gateway endpoint."
     type        = string
   }

   variable "allowed_s3_bucket_arns" {
     description = "ARN của các bucket được phép truy cập qua S3 gateway endpoint."
     type        = set(string)

     validation {
       condition     = length(var.allowed_s3_bucket_arns) > 0
       error_message = "Cần ít nhất một bucket ARN đã được xác nhận."
     }
   }
   ```

   Module có thể nhận Region từ root hoặc sử dụng convention provider sẵn có; không để Region biến module khác với Region provider. ARN mẫu trong `terraform.tfvars.example` phải là placeholder minh họa, không trỏ đến bucket thật không thuộc người học. Không khai báo credentials hoặc secret.

4. **Tạo gateway endpoint và policy giới hạn.** Trong `modules/networking/main.tf`, thêm resource tương đương:

   ```hcl
   resource "aws_vpc_endpoint" "s3" {
     vpc_id            = aws_vpc.this.id
     service_name      = "com.amazonaws.${var.aws_region}.s3"
     vpc_endpoint_type = "Gateway"
     route_table_ids   = [aws_route_table.private.id]

     policy = jsonencode({
       Version = "2012-10-17"
       Statement = [
         {
           Sid       = "ListApprovedBuckets"
           Effect    = "Allow"
           Principal = "*"
           Action    = ["s3:ListBucket"]
           Resource  = tolist(var.allowed_s3_bucket_arns)
         },
         {
           Sid       = "ReadObjectsFromApprovedBuckets"
           Effect    = "Allow"
           Principal = "*"
           Action    = ["s3:GetObject"]
           Resource = [
             for bucket_arn in var.allowed_s3_bucket_arns :
             "${bucket_arn}/*"
           ]
         }
       ]
     })

     tags = {
       Name        = "${var.environment_name}-s3-gateway-endpoint"
       Environment = var.environment_name
     }
   }
   ```

   Đây là endpoint policy tối thiểu minh họa cho đọc object và liệt kê bucket. `Principal = "*"` trong endpoint policy không tự cấp quyền cho mọi principal; request vẫn cần IAM authorization và chịu resource policy cùng các policy giới hạn khác. Thay `aws_vpc.this` và `aws_route_table.private` bằng resource/output thực tế. Nếu có nhiều private route table, truyền list ID được chọn thay vì hard-code một route table.

   Không thêm `aws_route` thủ công cho service prefix list nếu resource/provider tự quản lý route qua `route_table_ids`; tránh hai resource Terraform cùng quản lý route. Không cấu hình `private_dns_enabled` cho gateway endpoint: thuộc tính DNS private áp dụng cho interface endpoint, không phải gateway endpoint.

5. **Kết nối input từ root module.** Trong `dev/lab/main.tf`, cập nhật `module "networking"` hiện có để truyền input đúng một lần. Trong `dev/lab/variables.tf` và `terraform.tfvars.example`, khai báo/cung cấp các giá trị cấu hình không nhạy cảm cần thiết. Không tạo module call thứ hai cùng tên và không đặt bucket secret/data hoặc credentials trong variable.

6. **Format và validate.** Từ root `dev/lab/`, chạy:

   ```powershell
   terraform fmt -recursive
   terraform init
   terraform validate
   ```

   `terraform init` phải dùng backend/state hiện có; không khởi tạo state riêng cho endpoint. `terraform validate` kiểm tra cấu trúc HCL nhưng không chứng minh bucket ARN đúng, route table thuộc đúng VPC hay authorization của workload đã đủ.

7. **Review `terraform plan`.** Kiểm tra:

   - Đang dùng đúng AWS account, Region, root module `dev/lab/`, backend và state.
   - Endpoint type là `Gateway`, service name là S3 của đúng Region.
   - Chỉ các private route table đã chọn được liên kết; route table khác không bị thay đổi ngoài dự kiến.
   - Policy chỉ có các bucket ARN đã xác nhận và action cần thiết; object ARN có hậu tố `/*`.
   - Không có bucket policy, IAM role, NAT Gateway, VPC, subnet hoặc route khác bị xóa/thay thế ngoài phạm vi.
   - Plan không tạo interface endpoint có phí theo giờ.

   Nếu policy hiển thị ARN sai, route table association ngoài phạm vi hoặc có deletion/replacement, dừng và sửa trước khi apply. Endpoint policy là giới hạn truy cập, vì vậy sai policy có thể gây outage cho ứng dụng dù resource được tạo thành công.

8. **Apply chỉ khi được xác nhận.** Nếu người học đã xác nhận bucket sở hữu, policy, state, account/Region và thay đổi route, mới chạy `terraform apply`. Nếu không có bucket/workload thử nghiệm hoặc không được phép tạo thay đổi, dừng ở validate/plan; bài học vẫn có thể hoàn thành bằng cách phân tích plan.

9. **Kiểm thử bằng workload có quyền phù hợp (tùy chọn).** Chỉ khi có EC2/ECS workload lab được quản lý và đã được duyệt, dùng IAM role tạm thời để thử `ListBucket`/`GetObject` đến đúng bucket. Không bật public IP hoặc mở SG để thử endpoint. Xác minh action ngoài policy bị từ chối và một bucket khác không nằm trong allow-list không được truy cập qua endpoint. Phân biệt lỗi endpoint policy với lỗi IAM/bucket policy qua error, CloudTrail và cấu hình; không mở rộng policy tùy tiện chỉ để làm test xanh.

### Xác minh kết quả

- Trong AWS Console, mở VPC Endpoints và xác nhận endpoint S3 có trạng thái `Available`, đúng VPC/Region, type Gateway và gắn với đúng private route table.
- Mở route table và xác nhận route destination là AWS-managed S3 prefix list, target là VPC endpoint; route `local` và default route khác không bị mất.
- Đối chiếu endpoint policy với ARN/action yêu cầu. Không kết luận quyền truy cập chỉ từ việc endpoint ở trạng thái `Available`.
- Với workload test được phê duyệt, xác minh role có IAM permission, bucket policy không deny, DNS/Region đúng và request dùng endpoint route. Kiểm tra request được phép và request bị policy chặn.
- Nếu bucket policy có điều kiện `aws:SourceVpce`, xác minh mọi caller hợp lệ đều đi qua endpoint được phép trước khi bật điều kiện đó. Bài này không yêu cầu sửa bucket policy.
- Nếu không có workload test, ghi nhận kết quả là “cấu hình endpoint/route được plan hoặc triển khai đúng”, không khẳng định data-plane/application authorization đã được xác minh.
- Theo dõi CloudTrail/metrics/logs khi cần chẩn đoán; kiểm tra quyền truy cập và retention của log, cũng như phí ghi nhận nếu có.

### Xử lý lỗi thường gặp

| Triệu chứng | Nguyên nhân có thể có | Cách kiểm tra và khắc phục |
|---|---|---|
| Endpoint không ở trạng thái `Available` | VPC/Region/service name sai, quyền/quota hoặc lỗi cấu hình AWS | Kiểm tra trạng thái/message, Region, VPC, service support và quota; không xóa state để làm lại. |
| Workload vẫn gửi S3 traffic qua NAT | Route table của subnet chưa liên kết endpoint, workload dùng route table khác, Region/hostname không khớp hoặc endpoint route thiếu | Xác định subnet association thực tế, xem route prefix list, service Region/endpoint DNS và flow. |
| S3 trả `AccessDenied` dù endpoint hoạt động | IAM role thiếu action/resource, endpoint policy không cho phép, bucket policy/SCP/permission boundary deny | Kiểm tra từng policy layer và CloudTrail; chỉ bổ sung đúng permission cần thiết sau khi xác định lớp chặn. |
| `ListBucket` bị từ chối nhưng `GetObject` hoạt động | IAM/endpoint policy thiếu `s3:ListBucket` hoặc ARN bucket sai | Kiểm tra ListBucket dùng bucket ARN không có `/*`; GetObject dùng object ARN có `/*`. |
| Object read bị từ chối | `s3:GetObject` resource ARN không khớp object, endpoint/bucket policy deny, KMS key policy/permission nếu object dùng SSE-KMS | Kiểm tra chính xác object ARN và mọi authorization liên quan, gồm quyền KMS khi phù hợp; không mở bucket public. |
| Một hệ thống ngoài VPC không truy cập S3 qua endpoint | Gateway endpoint không phải transit endpoint cho peering/TGW/on-premises | Thiết kế endpoint/connectivity phù hợp cho nguồn đó; không giả định route table VPC endpoint được quảng bá sang mạng khác. |
| Interface endpoint DNS không phân giải private | Private DNS chưa bật, DNS support/hostnames hoặc resolver/configuration sai, SG endpoint chặn | Kiểm tra service/Region, VPC DNS attributes, endpoint private DNS, resolver và inbound rule TCP 443 từ workload cần thiết. |
| Plan tạo thêm route trùng hoặc route table không mong muốn | Thêm route thủ công cùng với endpoint route management hoặc chọn sai associations | Dùng một ownership pattern; kiểm tra `route_table_ids`, resource addresses và plan trước khi apply. |
| Terraform báo endpoint policy invalid | JSON không hợp lệ, action/resource ARN không tương thích hoặc thiếu cú pháp chính sách | Validate HCL và kiểm tra policy schema/action-resource mapping; tham chiếu policy mẫu chính thức của service, không đổi sang `*` để bỏ qua lỗi. |

### Dọn dẹp tài nguyên

S3 gateway endpoint có thể trở thành một phần networking dùng chung cho các section tiếp theo. Không xóa nó chỉ vì bài 6 đã kết thúc nếu workload hoặc module khác cần sử dụng. Việc xóa endpoint có thể gỡ route tương ứng khỏi route table đã liên kết và khiến traffic chuyển sang NAT hoặc mất kết nối.

Nếu endpoint chỉ là tài nguyên thử nghiệm, chủ sở hữu xác nhận không còn caller và có thể xóa:

1. Xác nhận đúng `dev/lab/` state, account, Region, VPC và route table.
2. Đọc plan xóa endpoint, kiểm tra route bị gỡ và tác động đến workload.
3. Chỉ apply deletion sau khi đã xác nhận đường truy cập thay thế và phạm vi.
4. Xác minh endpoint/route đã được dọn và chi phí/traffic không còn theo dõi resource đó.

Không chạy `terraform destroy` cho toàn bộ `dev/lab/`; không áp dụng cleanup này cho prod hoặc capstone. Production cần change approval, đánh giá caller, connectivity fallback và rollback riêng.

## 7. Bài tập tự kiểm tra

1. Giải thích khác nhau giữa gateway endpoint và interface endpoint về route/ENI, service hỗ trợ, security group, DNS và chi phí.
2. Một S3 gateway endpoint ở trạng thái `Available`, nhưng EC2 không đọc được object. Liệt kê ít nhất bốn lớp cần kiểm tra ngoài trạng thái endpoint.
3. Private subnet có default route đến NAT Gateway và route S3 prefix list đến gateway endpoint. Request đến S3 và request đến một website bất kỳ sẽ đi theo đường nào? Vì sao?
4. Một endpoint policy cho phép `s3:GetObject` đến bucket. Vì sao điều đó không đủ để một IAM role đọc object?
5. Nhóm vận hành định thêm `aws:SourceVpce` condition vào bucket policy để chỉ cho phép một endpoint. Nêu các caller và hệ thống phụ thuộc cần inventory trước khi triển khai.
6. Workload cần truy cập S3, DynamoDB và một dịch vụ AWS chỉ có interface endpoint trong Region. Hãy chọn endpoint type cho từng dịch vụ và nêu các chi phí/cấu hình cần xác minh.
7. Vì sao không thể dùng S3 gateway endpoint trong một VPC rồi kỳ vọng máy on-premises hoặc một VPC peer tự động dùng chung endpoint?

### Gợi ý đáp án

1. Gateway endpoint cho S3/DynamoDB tích hợp vào route table bằng service prefix list, không có endpoint ENI/SG và thường không tính phí theo giờ như interface endpoint. Interface endpoint dùng PrivateLink với ENI private trong subnet, SG, DNS/private DNS và phí theo thời gian/AZ cùng dữ liệu theo bảng giá.
2. Kiểm tra route table association và route prefix list, hostname/Region/DNS, endpoint policy, IAM identity policy, bucket policy, SCP/permission boundary/session policy, KMS permission nếu object dùng SSE-KMS, NACL/SG/route và credentials tạm thời của workload.
3. S3 destination khớp service prefix list route cụ thể đến gateway endpoint; website không khớp route đó và dùng route phù hợp khác, thường default route đến NAT Gateway nếu tồn tại. Endpoint không thay route cho toàn bộ Internet.
4. Endpoint policy là giới hạn bổ sung, không cấp identity permission. IAM role cần Allow đúng action/resource và không bị explicit Deny; bucket policy và policy giới hạn khác cũng phải cho phép.
5. Inventory ứng dụng/workload, account/role, replication, logging, backup, data processing, console/admin access, service integrations, cross-account access và endpoint ở các VPC/Region khác. Chuẩn bị endpoint allow-list và phương án break-glass có kiểm soát để tránh tự khóa.
6. S3 và DynamoDB có thể dùng gateway endpoint nếu phù hợp; service interface-only cần interface endpoint nếu muốn PrivateLink. Xác minh service/Region, route table associations, endpoint policy, IAM, SG/DNS cho interface endpoint, số AZ, phí giờ/data và khả năng vẫn cần NAT cho traffic còn lại.
7. Gateway endpoint route association thuộc route table trong VPC đó, không phải tuyến transit được quảng bá sang peer/TGW/on-premises. Cần một kiến trúc endpoint/connectivity riêng cho các nguồn ngoài VPC và xác minh giới hạn của service.

## Tổng kết kiến thức và nguyên tắc áp dụng

VPC endpoint cung cấp một con đường mạng riêng đến dịch vụ AWS được hỗ trợ, nhưng lựa chọn endpoint type phải dựa trên service và kiến trúc: gateway endpoint dùng route table cho S3/DynamoDB; interface endpoint dùng PrivateLink và ENI cho nhiều AWS service/endpoint service. Endpoint chỉ giải quyết connectivity. IAM, resource policy, endpoint policy, security group, NACL, DNS và TLS tiếp tục có vai trò riêng.

Đối với workload private, endpoint có thể giảm phụ thuộc vào NAT cho traffic đến service tương ứng, nhưng không tự thay thế NAT cho Internet egress. Hãy kiểm tra đúng route table, Region, hostname/DNS, policy và caller; đừng suy luận quyền truy cập từ trạng thái `Available`. Endpoint policy là một lớp giới hạn bổ sung, không phải IAM grant.

Trong thực tế, chọn endpoint bằng cách lập danh sách service mà workload cần gọi, xác minh service/Region/endpoint type, so sánh giá với NAT, thiết kế policy và DNS, rồi review plan trước khi triển khai. Mọi thay đổi endpoint hoặc resource policy có thể ảnh hưởng ứng dụng dùng chung; cần inventory caller, test trường hợp thành công/thất bại và phương án khôi phục trước khi thay đổi production.

Hãy áp dụng nguyên tắc này cho một ECS service chỉ cần đọc object từ S3, gửi log đến CloudWatch và gọi API thanh toán công khai: endpoint nào có thể giảm NAT traffic, endpoint type nào cần xem xét cho logging, traffic nào vẫn cần egress Internet, và những policy nào phải phối hợp để không mở quyền quá rộng?