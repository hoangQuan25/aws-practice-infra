# Section 1 — Bài 1: IAM fundamentals và nguyên tắc quyền tối thiểu

## Mục tiêu bài học

Sau bài này, người học có thể:

- Giải thích AWS Identity and Access Management (IAM) kiểm soát danh tính và quyền truy cập vào tài nguyên AWS như thế nào.
- Phân biệt IAM user, user group, IAM role và IAM policy; giải thích vai trò của trust policy và permissions policy.
- Phân tích một policy JSON để xác định principal, action, resource, điều kiện và hiệu lực Allow/Deny.
- Giải thích vì sao quyền mặc định là từ chối, explicit deny thắng allow, và vì sao một policy Allow chưa chắc đủ để một yêu cầu thành công.
- Thiết kế cách cấp quyền theo least privilege và xác định các bước cần làm để xác minh quyền.
- Quan sát các cấu hình IAM hiện có trong AWS Management Console mà không tạo hoặc sửa tài nguyên.

## 1. Bối cảnh và vấn đề

Một AWS account có thể chứa nhiều loại tài nguyên: máy ảo, cơ sở dữ liệu, bucket lưu trữ, hàm serverless và các dịch vụ mạng. Nếu mọi người và mọi ứng dụng đều có toàn quyền trên account, một lỗi thao tác hoặc credential bị lộ có thể dẫn đến rò rỉ dữ liệu, xóa nhầm tài nguyên hoặc phát sinh chi phí lớn.

IAM cung cấp cơ chế xác định:

1. **Ai hoặc thành phần nào đang gửi yêu cầu?** Đây là danh tính/principal.
2. **Danh tính đó muốn gọi thao tác nào?** Đây là action, thường tương ứng với một API operation của AWS.
3. **Thao tác đó nhắm tới tài nguyên nào?** Đây là resource.
4. **Yêu cầu có thỏa các điều kiện bổ sung không?** Ví dụ như vùng, địa chỉ IP, tag hoặc thông tin phiên.

Ví dụ: một dịch vụ chạy trong Amazon ECS cần đọc mật khẩu cơ sở dữ liệu từ AWS Secrets Manager. Dịch vụ đó cần một IAM role gắn với ECS task, và role chỉ nên được đọc đúng secret mà task cần. Nếu task được cấp quyền quản trị toàn bộ account, việc chiếm quyền điều khiển task có thể trở thành sự cố trên toàn account thay vì chỉ làm lộ một secret.

IAM là trọng tâm của xác thực và phân quyền, nhưng không thay thế mọi lớp bảo mật khác. IAM không tự mã hóa dữ liệu, không thay thế security group hay network ACL, và không ngăn ứng dụng xử lý sai dữ liệu mà nó đã được phép đọc. Một thiết kế an toàn thường kết hợp IAM với bảo vệ mạng, mã hóa, quản lý secret, logging và quy trình vận hành.

## 2. Khái niệm và thành phần cốt lõi

### Principal, authentication và authorization

**Principal** là danh tính đại diện cho người hoặc thành phần gửi yêu cầu đến AWS. Principal có thể là một IAM user, một phiên được assume từ IAM role, một dịch vụ AWS hoạt động thay mặt role, hoặc một danh tính liên kết/federated từ hệ thống đăng nhập khác.

Hai bước cần phân biệt:

- **Authentication — xác thực:** AWS kiểm tra danh tính của bên gửi yêu cầu. Ví dụ: đăng nhập bằng thông tin xác thực hợp lệ hoặc sử dụng thông tin xác thực tạm thời do STS cấp.
- **Authorization — phân quyền:** Sau khi biết danh tính, AWS xác định danh tính đó có được phép thực hiện action trên resource trong context hiện tại hay không.

Đăng nhập thành công không có nghĩa là được phép gọi mọi API. Tương tự, một ứng dụng có thể khởi chạy bình thường nhưng vẫn nhận lỗi `AccessDenied` khi role của nó thiếu quyền với một resource cụ thể.

### IAM user

IAM user là một danh tính được tạo trong AWS account. IAM user có thể được cấu hình để đăng nhập AWS Management Console hoặc có access key để gọi AWS API. Việc tồn tại một IAM user không tự động cấp quyền; quyền hiệu lực còn phụ thuộc vào policy và các giới hạn áp dụng.

Đối với nhân viên hoặc người vận hành, không nên mặc định tạo một IAM user cục bộ cho mỗi người. Trong nhiều tổ chức, AWS IAM Identity Center hoặc một hệ thống federation được ưu tiên để quản lý đăng nhập tập trung và cấp phiên truy cập tạm thời. IAM user vẫn có thể xuất hiện trong hệ thống cũ hoặc một số trường hợp đặc thù, nhưng cần kiểm soát chặt credential, MFA và vòng đời của danh tính.

### IAM user group

IAM user group là một tập hợp các IAM user, giúp gắn cùng policy cho nhiều user có cùng nhu cầu công việc, chẳng hạn nhóm chỉ cần xem tài nguyên. Khi một user là thành viên của group, quyền được cấp cho group có thể áp dụng cho user đó.

Group không phải danh tính đăng nhập, không thể assume role và không thể được dùng làm principal trong trust policy. Group chỉ giúp tổ chức quyền cho IAM users; nó không phải cơ chế quản lý workload identity.

### IAM role và AWS STS

IAM role là một danh tính có permissions policy, nhưng không gắn với một bộ mật khẩu hoặc access key dài hạn như một số cách dùng IAM user. Một principal được phép **assume role** có thể nhận thông tin xác thực tạm thời thông qua AWS Security Token Service (AWS STS), rồi sử dụng phiên đó để gọi các API trong phạm vi role cho phép.

Các ví dụ thường gặp:

- Amazon EC2 instance sử dụng instance profile để nhận role và gọi API AWS.
- AWS Lambda function sử dụng execution role để ghi log hoặc đọc một secret.
- ECS task sử dụng task role để ứng dụng bên trong task gọi AWS API.
- Một người vận hành hoặc một dịch vụ ở AWS account khác assume role nếu trust relationship cho phép và các điều kiện phân quyền liên quan đều được đáp ứng.

Một role có hai mặt cần phân biệt:

1. **Trust policy (assume role policy):** xác định principal nào được phép assume role và có thể đặt điều kiện cho việc assume.
2. **Permissions policies:** xác định những action role được phép thực hiện trên các resource trong thời gian phiên hoạt động.

```text
Principal ── yêu cầu assume role ──► Trust policy quyết định có tin cậy không
                                             │
                                             ▼
                                  AWS STS cấp credentials tạm thời
                                             │
                                             ▼
                                  Permissions policy giới hạn action
                                             │
                                             ▼
                                      AWS resource
```

Trust policy không cấp quyền đọc S3 hay gọi DynamoDB; nó chỉ kiểm soát ai có thể nhận role. Ngược lại, permissions policy không tự cho phép một principal bất kỳ assume role nếu trust policy không cho phép.

### IAM policy

IAM policy là tài liệu JSON mô tả quyền hoặc giới hạn quyền. Các policy có thể được AWS quản lý hoặc do người dùng tạo. Policy có thể gắn với danh tính (identity-based policy), hoặc được đặt trên tài nguyên để điều khiển truy cập vào tài nguyên đó (resource-based policy), tùy dịch vụ hỗ trợ.

Một statement trong policy thường có các thành phần:

- `Effect`: `Allow` để cho phép hoặc `Deny` để từ chối.
- `Action` hoặc `NotAction`: các thao tác API được nêu rõ hoặc loại trừ.
- `Resource` hoặc `NotResource`: tài nguyên mà statement áp dụng.
- `Condition` (không bắt buộc): điều kiện bổ sung, ví dụ giới hạn theo tag hoặc context của yêu cầu.
- `Principal`: xuất hiện trong một số policy dạng resource-based hoặc trust policy để chỉ định danh tính liên quan; không phải thành phần dùng giống nhau trong mọi identity-based policy.

Ví dụ dưới đây minh họa một quyền hẹp: cho phép đọc object dưới prefix `reports/` trong một bucket giả định.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadReportsOnly",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::example-training-bucket/reports/*"
    }
  ]
}
```

Trong ví dụ:

- `s3:GetObject` cho phép đọc nội dung object, không cho phép ghi hoặc xóa object.
- ARN kết thúc bằng `reports/*` giới hạn quyền ở các object nằm dưới prefix `reports/`.
- Policy không cấp `s3:ListBucket`. Việc liệt kê object là một action riêng và thường dùng ARN của bucket, không phải ARN object.
- `example-training-bucket` chỉ là tên minh họa; policy này chưa được gắn vào danh tính nào và không tạo quyền thực tế.

### Các loại policy và giới hạn quyền

| Loại policy/guardrail | Vai trò | Điều cần nhớ |
|---|---|---|
| Identity-based policy | Cấp hoặc từ chối quyền cho IAM user, group hoặc role | Quyền thường gắn với danh tính và được đánh giá cùng các giới hạn khác |
| Resource-based policy | Đặt quyền trực tiếp trên một số tài nguyên, ví dụ bucket hoặc secret | Chỉ dùng được với dịch vụ hỗ trợ; cần xem cả principal và policy của tài nguyên |
| Trust policy | Xác định principal được phép assume role | Không cấp các action sử dụng tài nguyên sau khi role được nhận |
| Permissions boundary | Đặt mức quyền tối đa mà identity-based permissions có thể cấp cho một user hoặc role | Không tự cấp quyền; chỉ giới hạn quyền tối đa |
| Service Control Policy (SCP) | Đặt giới hạn quyền tối đa cho account hoặc organizational unit trong AWS Organizations | Không cấp quyền; một action bị SCP chặn không thể được identity policy cấp lại |
| Session policy | Giới hạn quyền của phiên assume role trong một số luồng STS | Có thể làm hẹp quyền của phiên; không phải cơ chế để mở rộng vượt quyền role |

Mô hình trên là khái quát. Cách kết hợp policy cụ thể phụ thuộc vào loại principal, loại policy, cùng hay khác account, dịch vụ và cách principal được đại diện trong policy tài nguyên. Không nên kết luận quyền hiệu lực chỉ bằng cách nhìn một policy đơn lẻ.

## 3. Cách IAM đánh giá một yêu cầu

Một cách suy luận an toàn là bắt đầu từ câu hỏi cụ thể: “Principal này có được gọi action này trên resource này trong context này không?”. AWS đánh giá yêu cầu dựa trên các policy liên quan và những giới hạn đang áp dụng.

```text
Yêu cầu AWS
  │
  ├─ Xác định principal, action, resource và context
  │
  ├─ Có explicit Deny áp dụng? ───── Có ──► Từ chối
  │
  ├─ Có Allow phù hợp không? ─────── Không ► Từ chối mặc định
  │
  ├─ Có guardrail hoặc giới hạn nào chặn?
  │
  └─ Các điều kiện và chính sách liên quan đều cho phép
                                      │
                                      ▼
                                    Cho phép
```

Các nguyên tắc nền tảng:

1. **Implicit deny:** Nếu không có policy phù hợp cho phép yêu cầu, kết quả mặc định là từ chối. Việc một IAM user, role hay resource tồn tại không tự tạo quyền.
2. **Explicit deny thắng:** Nếu một policy áp dụng rõ ràng `Deny` cho yêu cầu, một `Allow` khác không thể ghi đè explicit deny đó.
3. **Allow cần đúng phạm vi:** Action, resource và condition trong policy phải khớp với yêu cầu thật. Sai ARN, sai prefix, action chưa được nêu hoặc condition không thỏa đều có thể khiến yêu cầu bị từ chối.
4. **Guardrail có thể giới hạn quyền:** Permissions boundary, SCP, session policy và các policy khác có thể thu hẹp tập quyền hiệu lực. SCP và permissions boundary là giới hạn, không phải nguồn cấp quyền.
5. **Resource policy có thể ảnh hưởng kết quả:** Với dịch vụ hỗ trợ resource-based policy, cần xem policy gắn với tài nguyên. Truy cập xuyên account thường cần cấu hình tin cậy và cấp quyền ở các phía liên quan; kiểm tra trường hợp cụ thể theo loại principal và dịch vụ.

Vì vậy, khi gặp lỗi `AccessDenied`, đừng vội gắn `AdministratorAccess`. Hãy xác định chính xác principal thực tế của yêu cầu, action được gọi, ARN resource, region/account, context condition và các policy/guardrail liên quan. Nếu quyền đã được cấp nhưng không đúng resource hoặc điều kiện, thêm policy rộng hơn sẽ làm tăng rủi ro mà chưa chắc sửa đúng nguyên nhân.

## 4. Least privilege và tư duy kiến trúc

**Least privilege (nguyên tắc quyền tối thiểu)** là chỉ cấp đúng những quyền cần thiết cho một danh tính để thực hiện một nhiệm vụ, trong phạm vi resource và khoảng thời gian cần thiết. Nguyên tắc này giới hạn tác động khi ứng dụng bị khai thác, cấu hình sai hoặc credentials bị lộ.

Khi thiết kế policy cho một workload, đi theo các bước sau:

1. **Xác định principal:** Xác định chính xác workload hoặc người dùng sẽ gửi API request. Ví dụ, ứng dụng ECS cần dùng task role của ECS task, không nên dùng quyền của người triển khai.
2. **Liệt kê thao tác cần thiết:** Dựa trên luồng ứng dụng và tài liệu API, xác định những action thực sự cần. Phân biệt đọc, ghi, liệt kê, sửa đổi và xóa; các thao tác này thường là action riêng.
3. **Giới hạn resource:** Dùng ARN của bucket, secret, key, queue hoặc tài nguyên cụ thể khi dịch vụ hỗ trợ. Nếu action bắt buộc dùng `Resource: "*"`, giải thích lý do và kiểm tra xem có thể giới hạn bằng condition hay không.
4. **Thêm condition khi có lợi:** Có thể giới hạn thêm theo tag, vùng, nguồn gọi hoặc context khác nếu condition đó được dịch vụ hỗ trợ và không phá vỡ luồng hợp lệ.
5. **Chọn thời hạn và cách cấp credential:** Ưu tiên role và credentials tạm thời cho workload; tránh tạo access key dài hạn không cần thiết.
6. **Kiểm chứng quyền dương và quyền âm:** Xác nhận thao tác cần thiết thành công, đồng thời xác nhận workload không thể thực hiện thao tác nhạy cảm hoặc truy cập tài nguyên ngoài phạm vi.
7. **Rà soát theo thay đổi:** Khi ứng dụng thêm chức năng, cập nhật quyền có chủ đích; thu hồi quyền không còn cần thiết.

Policy rộng như `Action: "*"` hoặc `Resource: "*"` không tự động là sai trong mọi ngữ cảnh, nhưng làm tăng đáng kể phạm vi tác động và cần lý do, giới hạn khác cùng biện pháp giám sát rõ ràng. Không dùng quyền quản trị toàn phần như giải pháp mặc định cho lỗi triển khai hoặc `AccessDenied`.

### Bảo vệ tài khoản và credentials

- Bật Multi-Factor Authentication (MFA) cho root user và không dùng root user cho công việc hằng ngày.
- Không tạo access key cho root user.
- Dùng IAM Identity Center hoặc federation cho người vận hành khi môi trường hỗ trợ.
- Dùng IAM role và credentials tạm thời cho EC2, Lambda, ECS, CI/CD và các workload khác.
- Không commit access key, mật khẩu, secret, private key hoặc file credentials vào source control; không in chúng ra log hay chia sẻ trong ảnh chụp màn hình.
- Thu hồi credentials không còn sử dụng và điều tra ngay nếu nghi ngờ chúng bị lộ.
- Ghi nhớ rằng bảo vệ quyền IAM cần đi cùng logging, giám sát, bảo mật mạng và bảo vệ dữ liệu.

### Tính sẵn sàng và khả năng phục hồi

IAM là dịch vụ quản lý danh tính, không phải cơ chế dự phòng cho ứng dụng hoặc dữ liệu. Bài học này không triển khai Multi-AZ hay backup. Tuy nhiên, role và quyền cần được thiết kế để workload có thể tiếp tục hoạt động theo kiến trúc dự phòng dự kiến: ví dụ role gắn đúng với task/service thay vì phụ thuộc vào một access key thủ công trên một máy.

Việc cấp quyền quá hẹp hoặc cấu hình trust policy sai có thể khiến workload dự phòng không khởi chạy hoặc không truy cập được dependency sau failover. Do đó cần kiểm thử role trong luồng triển khai thực tế và xác minh mọi instance/task thay thế đều nhận đúng role, không cấp quyền rộng để né lỗi.

### Bảo mật

Least privilege làm giảm phạm vi ảnh hưởng nhưng không đảm bảo workload không thể bị khai thác. Cần bảo vệ trust policy để chỉ đúng principal có thể assume role, hạn chế actions/resources trong permissions policy, bảo vệ credentials, và kiểm tra resource policy hoặc Organizations guardrails nếu có.

Khi ứng dụng cần secret, quyền đọc secret nên chỉ gắn với workload cần nó và ARN của secret cụ thể. Nếu secret dùng customer managed KMS key, việc đọc có thể cần thêm quyền giải mã phù hợp. Không lưu secret trực tiếp trong mã nguồn hoặc `terraform.tfvars`; giá trị nhạy cảm có thể xuất hiện trong Terraform state tùy cách tạo và quản lý tài nguyên, nên state cần được bảo vệ như dữ liệu nhạy cảm.

### Chi phí

Các thao tác quan sát IAM trong bài này không tạo tài nguyên hạ tầng tính phí. Lab chỉ đọc cấu hình hiện có và phân tích policy ví dụ, nên không cần `terraform apply` hoặc `terraform destroy`. Tài nguyên khác đang tồn tại trong AWS account vẫn có thể phát sinh phí độc lập với bài học này.

Một số dịch vụ được bảo vệ bởi IAM hoặc được tích hợp cùng IAM (ví dụ Secrets Manager, KMS, CloudTrail hoặc dịch vụ compute) có thể có chi phí riêng theo cách sử dụng. Không suy luận rằng một workload không tốn phí chỉ vì IAM không tạo máy chủ hay database.

### Lựa chọn kiến trúc và đánh đổi

- Với người dùng cần truy cập Console, đăng nhập tập trung thường dễ quản lý và thu hồi hơn việc tạo nhiều IAM users riêng lẻ.
- Với workload chạy trên AWS, role và credentials tạm thời tránh phải phân phối access key dài hạn, nhưng cần cấu hình đúng trust relationship và gắn role vào đúng dịch vụ.
- Policy càng giới hạn chính xác thì phạm vi ảnh hưởng càng nhỏ, nhưng policy sai hoặc chưa cập nhật theo thay đổi ứng dụng có thể làm gián đoạn luồng hợp lệ. Cần theo dõi lỗi quyền và cập nhật policy dựa trên nhu cầu đã được xác minh.
- Resource-based policy hữu ích khi cần kiểm soát truy cập ngay tại tài nguyên hoặc chia sẻ resource; chúng làm mô hình phân quyền phức tạp hơn, nhất là khi truy cập xuyên account.
- Role và policy IAM không thay thế security group, network ACL, mã hóa hoặc kiểm soát ở tầng ứng dụng; chúng giải quyết một lớp khác của mô hình bảo mật.

## 5. Quan sát trên AWS Management Console

Phần Console này chỉ quan sát cấu hình. AWS có thể thay đổi cách đặt tên hoặc bố cục mục trong Console; nếu nhãn khác, dùng thanh tìm kiếm trong Console để mở dịch vụ IAM. Không sửa policy, tạo user, tạo access key hoặc thay đổi thiết lập account.

1. **Xác nhận account và danh tính đăng nhập.** Đăng nhập bằng phương thức được tổ chức hoặc chủ tài khoản cấp. Kiểm tra account/role đang dùng từ thanh điều hướng tài khoản. Không dùng root user cho thao tác thường ngày và không tiếp tục nếu chưa chắc mình đang ở account đúng.
2. **Mở IAM.** Dùng thanh tìm kiếm dịch vụ và mở **IAM**. Đây là điểm quan sát cấu hình danh tính và policy của account; IAM không cần chọn một region cụ thể như nhiều dịch vụ tài nguyên.
3. **Quan sát Dashboard hoặc Security recommendations.** Nếu có, xem các khuyến nghị bảo mật liên quan đến root, MFA hoặc credentials. Chỉ ghi nhận trạng thái; đừng thay đổi cài đặt nếu không phải account bạn có quyền quản trị.
4. **Quan sát Users và User groups.** Mở các mục **Users** và **User groups** nếu chúng hiện diện và bạn có quyền xem. Nhận biết user là danh tính, group là cách tổ chức quyền cho user. Không mở, sao chép hay ghi lại secret access key, mật khẩu hoặc thông tin nhạy cảm khác. Một tổ chức có thể quản lý workforce identity qua IAM Identity Center/federation, vì vậy IAM users có thể không đại diện cho toàn bộ nhân viên.
5. **Quan sát Roles.** Mở một role hiện có mà bạn được phép xem. Trong phần trust relationship, xác định dịch vụ hoặc principal nào được phép assume role. Trong phần permissions, xem policy được gắn trực tiếp hoặc qua managed policy và nhận diện một vài action/resource. Không bấm **Edit**, **Add permissions** hay **Delete**.
6. **Đọc một policy.** Nếu được phép xem chi tiết policy, xác định `Effect`, `Action`, `Resource` và `Condition`. So sánh các trường đó với ví dụ `s3:GetObject` trong bài. Không thay đổi policy.
7. **Tìm công cụ phân tích nếu có.** Nếu account cung cấp IAM Access Analyzer hoặc IAM Policy Simulator, xem mô tả và giao diện ở chế độ quan sát. Không tạo analyzer, không áp dụng policy, và không đưa vào công cụ bất kỳ dữ liệu nhạy cảm nào.

Sau khi quan sát, hãy viết câu trả lời cho các câu hỏi sau:

- Danh tính nào đang được xem, và đây là user hay role?
- Nếu là role, principal nào được phép assume role theo trust policy?
- Policy nào định nghĩa quyền của danh tính? Nêu một action và một resource cụ thể nếu chúng hiển thị.
- Có thể kết luận một yêu cầu API sẽ thành công chỉ từ policy đang xem không? Những giới hạn hoặc điều kiện nào khác có thể cần kiểm tra?

Nếu bạn không có quyền xem các trang này, không xin quyền quản trị rộng hơn chỉ để hoàn thành bài. Dùng ví dụ policy trong tài liệu để luyện phân tích và ghi rõ phần nào bạn không thể xác nhận từ account.

## 6. Thực hành

> **Mục tiêu:** Phân tích policy ví dụ theo principal, action, resource và condition; xác định yêu cầu nào được cho phép hoặc bị từ chối theo phạm vi ví dụ.  
> **Môi trường:** Bài tập cục bộ và quan sát Console tùy quyền; không triển khai Terraform và không thay đổi AWS account.  
> **Chi phí dự kiến:** Bản thân bài phân tích không tạo tài nguyên và không phát sinh phí AWS.  
> **Rủi ro và phạm vi:** Không tạo hoặc chỉnh IAM user, role, policy, access key hay credentials. Không dán policy vào account thật và không chạy lệnh thay đổi quyền.

### Kiến trúc bài tập

Bài tập sử dụng một IAM role giả định tên `ReportReaderRole` và một bucket minh họa tên `example-training-bucket`. Policy chỉ cho phép `s3:GetObject` trên các object nằm dưới prefix `reports/`. Đây là ví dụ phân tích, không phải mã triển khai; tên bucket có thể không tồn tại.

```text
ReportReaderRole
      │
      ├── s3:GetObject trên arn:aws:s3:::example-training-bucket/reports/*
      │       └── Có thể đọc object phù hợp trong prefix reports/
      │
      ├── s3:PutObject
      │       └── Không được policy ví dụ cho phép
      │
      └── s3:GetObject trên prefix khác
              └── Không khớp resource được Allow
```

Trong một hệ thống thật, còn cần xem role có được principal assume hay không, có policy/guardrail khác áp dụng không, và bucket có resource-based policy hoặc cấu hình bổ sung nào ảnh hưởng đến yêu cầu không.

### Điều kiện trước khi bắt đầu

- Có thể đọc nội dung bài này và ghi chú kết quả trong một trình soạn thảo cục bộ.
- Nếu muốn làm phần Console, có AWS account và quyền chỉ đọc IAM phù hợp. Không yêu cầu quyền tạo hoặc sửa IAM resources.
- Không cần AWS CLI, Terraform, access key, private key hay secret.

### Các bước thực hiện

1. **Đọc policy và xác định phạm vi.** Từ JSON ở phần “IAM policy”, ghi ra `Effect`, `Action` và `Resource`. Giải thích bằng câu của bạn: action nào được cho phép, object nào thuộc phạm vi, và những hành động nào không được nêu.
2. **Đánh giá ba yêu cầu giả định.** Với từng yêu cầu dưới đây, kết luận “được policy ví dụ cho phép” hoặc “không được policy ví dụ cho phép”, rồi giải thích trường policy khiến bạn kết luận như vậy:
   - `s3:GetObject` trên `arn:aws:s3:::example-training-bucket/reports/2026/summary.csv`.
   - `s3:PutObject` trên `arn:aws:s3:::example-training-bucket/reports/2026/summary.csv`.
   - `s3:GetObject` trên `arn:aws:s3:::example-training-bucket/archive/summary.csv`.
3. **Phân biệt đọc object và liệt kê bucket.** Giải thích vì sao `s3:GetObject` trên ARN object không tự cấp `s3:ListBucket`. Chỉ ra rằng các thao tác và ARN tương ứng cần được kiểm tra riêng theo tài liệu IAM của S3.
4. **Xác định giới hạn của kết luận.** Nêu những gì ví dụ cho phép bạn kết luận về action/resource và những gì chưa thể kết luận: ví dụ role có thể được assume không, có explicit deny không, hoặc có SCP/boundary/resource policy tác động không.
5. **Thiết kế quyền cho tình huống mới.** Giả sử một Lambda function chỉ cần lấy giá trị của một secret cụ thể. Viết mô tả bằng ngôn ngữ thường cho principal, action tối thiểu, resource cần giới hạn và cách xác minh rằng function không đọc được secret khác. Không tạo policy trên account thật.
6. **Quan sát role trong Console (tùy chọn).** Nếu được cấp quyền xem, làm theo Section 5 và đối chiếu cấu trúc role thật với role giả định. Không thay đổi cấu hình. Nếu không được cấp quyền, ghi rõ bài tập đã hoàn thành bằng ví dụ giả định.

### Xác minh kết quả

Đối chiếu câu trả lời với các tiêu chí sau:

- Yêu cầu đọc object dưới `reports/` khớp với action `s3:GetObject` và ARN resource được Allow.
- Yêu cầu ghi object không khớp action được Allow, vì policy chỉ nêu `s3:GetObject`.
- Yêu cầu đọc object dưới prefix `archive/` không khớp ARN resource `reports/*`.
- Không thể kết luận role thật có thể được assume hoặc yêu cầu thật chắc chắn thành công chỉ bằng policy minh họa; cần kiểm tra trust relationship và các policy/guardrail khác áp dụng.
- `s3:ListBucket` là action riêng và không được cấp bởi `s3:GetObject`. Tài nguyên và ARN cần dùng phải được xác minh theo loại API S3.

Nếu câu trả lời của bạn dùng “AWS chắc chắn từ chối” chỉ dựa trên việc một action không có trong policy minh họa, hãy diễn đạt chính xác hơn: **policy minh họa này không cấp quyền đó**. Kết luận cuối cùng về request thật phải xét mọi policy và context liên quan.

### Xử lý lỗi thường gặp

| Triệu chứng hoặc nhầm lẫn | Nguyên nhân có thể có | Cách kiểm tra và khắc phục |
|---|---|---|
| Cho rằng user group là principal có thể assume role | Nhầm group với user hoặc role | Nhớ rằng group chỉ tổ chức IAM users; xem principal trong trust policy là user, role, account hoặc dịch vụ phù hợp |
| Cho rằng trust policy cấp quyền đọc/ghi resource | Gộp trust policy với permissions policy | Đọc trust policy để biết ai được assume; đọc permissions policy để biết role được làm gì |
| Cho rằng `Allow` trong một policy đảm bảo API luôn thành công | Bỏ qua explicit deny, điều kiện, boundary, SCP, session hoặc resource policy | Kiểm tra principal, action, resource, context và mọi guardrail/policy áp dụng |
| Cho rằng `s3:GetObject` cho phép xem danh sách bucket | Nhầm API đọc object với API liệt kê bucket | Kiểm tra action và loại ARN của từng thao tác riêng |
| Policy có action đúng nhưng vẫn gặp `AccessDenied` | ARN sai, prefix không khớp, condition không thỏa hoặc thiếu quyền ở lớp khác | So sánh ARN request thực tế với policy; kiểm tra condition, trust relationship và guardrails |
| Workload không assume được role | Principal không khớp trust policy hoặc service chưa được cấu hình dùng role | Kiểm tra trust relationship và cấu hình gắn role; không khắc phục bằng cách cấp quyền quản trị cho workload |

### Dọn dẹp tài nguyên

Không có tài nguyên nào được tạo trong bài tập này. Không chạy `terraform destroy`, không xóa IAM resources trong account và không cần dọn dẹp trên Console. Nếu bạn đã mở IAM Policy Simulator, chỉ đóng trang sau khi hoàn tất; không lưu hay áp dụng policy.

## 7. Bài tập tự kiểm tra

Trả lời từng câu bằng lập luận và ví dụ cụ thể. Với câu hỏi quyền truy cập, nêu principal, action và resource thay vì chỉ trả lời “có” hoặc “không”.

1. Một IAM user và một IAM role khác nhau thế nào về danh tính và cách nhận credentials? Vì sao role thường phù hợp với workload chạy trên AWS?
2. Trust policy và permissions policy của một role trả lời hai câu hỏi khác nhau nào? Dùng ví dụ ECS task đọc secret để giải thích.
3. Một policy identity-based cho phép `s3:GetObject` trên object trong prefix `reports/`. Điều đó có đồng nghĩa principal có thể liệt kê bucket, ghi object hoặc đọc prefix khác không? Giải thích từng trường hợp dựa trên `Action` và `Resource`.
4. Một request khớp với `Allow` trong identity policy nhưng bị một SCP áp dụng explicit deny. Kết quả là gì? Vì sao thêm một `Allow` khác không giải quyết được?
5. Một Lambda function cần đọc một secret nhưng nhận `AccessDenied`. Hãy mô tả trình tự chẩn đoán có least privilege, gồm principal, action, ARN secret, quyền KMS có thể liên quan, trust/execution role và guardrails. Giải thích vì sao không nên gắn `AdministratorAccess`.
6. Hãy đề xuất hai phép thử: một request cần được phép và một request cần bị từ chối, để xác minh policy của `ReportReaderRole` không cấp quyền vượt quá yêu cầu.

### Gợi ý đáp án

1. IAM user là danh tính trong account có thể được cấu hình để đăng nhập Console hoặc gọi API bằng credentials tương ứng. IAM role được một principal đủ điều kiện assume để nhận credentials tạm thời. Workload dùng role tránh phải nhúng access key dài hạn vào máy chủ hoặc mã nguồn và cho phép quản lý quyền theo vòng đời của workload.
2. Trust policy trả lời “principal nào được phép assume role?”; permissions policy trả lời “sau khi nhận role, role được phép gọi API nào trên resource nào?”. Với ECS, trust policy cần cho phép principal dịch vụ phù hợp assume task role; permissions policy có thể cho phép action đọc secret cụ thể. Cấu hình một phía đúng không tự sửa được phía còn lại.
3. Không. Policy chỉ nêu `s3:GetObject` trên ARN object `reports/*`. Nó không cấp `s3:PutObject`, không cấp `s3:ListBucket`, và không khớp object trong `archive/`. Đây là kết luận về policy minh họa; request thật còn có thể bị ảnh hưởng bởi các policy/guardrail khác.
4. Request bị từ chối vì explicit deny trong SCP là giới hạn tổ chức. SCP không cấp quyền, và identity policy Allow không thể vượt giới hạn này. Cần thay đổi theo quy trình quản trị tổ chức nếu quyền đó thật sự cần thiết, không thêm policy rộng hơn vào workload.
5. Bắt đầu bằng việc xác định function đang dùng execution role nào và request thực sự xuất phát từ principal nào. Kiểm tra action đọc secret cần thiết, ARN secret và region/account; kiểm tra trust/execution role, policy gắn với role, resource policy nếu có, SCP/boundary/session limits và quyền KMS nếu customer managed key yêu cầu. Sau đó kiểm thử đọc đúng secret và xác nhận không đọc được secret khác. `AdministratorAccess` tăng phạm vi thiệt hại, che khuất nguyên nhân thật và không đáp ứng least privilege.
6. Phép thử dương: gọi `s3:GetObject` cho một object dưới `reports/` và xác nhận request khớp policy. Phép thử âm: thử `s3:PutObject` lên object đó hoặc `s3:GetObject` trên object trong `archive/` và xác nhận policy này không cấp quyền. Chỉ thực hiện kiểm thử thật trong account/lab được phép; bài học hiện tại chỉ yêu cầu phân tích giả định.

## Tổng kết kiến thức và nguyên tắc áp dụng

IAM giúp xác định danh tính của bên gửi request và đánh giá quyền của request trên một resource cụ thể. Luôn phân tích theo principal, action, resource và context. Quyền mặc định là từ chối; `Allow` phù hợp là cần thiết nhưng có thể bị explicit deny hoặc giới hạn khác chặn. Khi điều tra lỗi quyền, hãy tìm nguyên nhân chính xác thay vì cấp quyền quản trị rộng để làm lỗi biến mất.

Với workload, ưu tiên role và credentials tạm thời. Trust policy kiểm soát ai được nhận role, còn permissions policy kiểm soát các hành động sau khi role được nhận. Áp dụng least privilege bằng cách giới hạn action, resource và condition theo nhu cầu đã xác minh; kiểm tra cả luồng được phép và luồng phải bị từ chối.

Bài này chỉ quan sát cấu hình IAM hiện có và phân tích policy giả định; không tạo tài nguyên, không thay đổi quyền và không phát sinh phí AWS từ lab. Khi áp dụng cho một ứng dụng mới, hãy tự hỏi: “Ứng dụng gọi API nào, bằng principal nào, trên ARN nào, trong điều kiện nào, và bằng phép thử nào tôi chứng minh nó không thể truy cập phần còn lại của account?”
