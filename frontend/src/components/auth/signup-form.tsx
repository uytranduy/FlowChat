import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { z } from "zod";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Label } from "../ui/label";
import { useAuthStore } from "@/stores/useAuthStore";
import { useNavigate } from "react-router";
import { GoogleSignInButton } from "./google-sign-in-button";

const specialCharacterPattern = /[!@#$%^&*(),.?":{}|<>_\-+=]/;

function passwordStrength(password: string) {
  const score = [
    password.length >= 6,
    password.length >= 10,
    /[a-z]/.test(password),
    /[A-Z]/.test(password),
    /\d/.test(password),
    specialCharacterPattern.test(password),
  ].filter(Boolean).length;

  if (score >= 5 && specialCharacterPattern.test(password)) {
    return { label: "Mạnh", width: "100%", color: "bg-emerald-500" };
  }
  if (score >= 3 && password.length >= 6 && specialCharacterPattern.test(password)) {
    return { label: "Trung bình", width: "66%", color: "bg-amber-500" };
  }
  return { label: "Yếu", width: "33%", color: "bg-red-500" };
}

const signUpSchema = z.object({
  firstname: z.string().min(1, "Tên bắt buộc phải có"),
  lastname: z.string().min(1, "Họ bắt buộc phải có"),
  username: z.string().min(3, "Tên đăng nhập phải có ít nhất 3 ký tự"),
  email: z.email("Email không hợp lệ"),
  password: z
    .string()
    .min(6, "Mật khẩu phải có ít nhất 6 ký tự")
    .regex(
      specialCharacterPattern,
      "Mật khẩu phải có ít nhất một ký tự đặc biệt, ví dụ @ hoặc !"
    ),
});

type SignUpFormValues = z.infer<typeof signUpSchema>;

export function SignupForm({ className, ...props }: React.ComponentProps<"div">) {
  const { signUp, signInWithGoogle, loading } = useAuthStore();
  const navigate = useNavigate();
  const {
    register,
    watch,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<SignUpFormValues>({
    resolver: zodResolver(signUpSchema),
  });
  const password = watch("password", "");
  const strength = passwordStrength(password);

  const onSubmit = async (data: SignUpFormValues) => {
    const { firstname, lastname, username, email, password } = data;

    // gọi backend để signup
    if (await signUp(username, password, email, firstname, lastname)) {
      navigate("/signin");
    }
  };

  const onGoogleCredential = async (idToken: string) => {
    if (await signInWithGoogle(idToken)) navigate("/");
  };

  return (
    <div
      className={cn("flex flex-col gap-6", className)}
      {...props}
    >
      <Card className="overflow-hidden p-0 border-border">
        <CardContent className="grid p-0 md:grid-cols-2">
          <form
            className="p-6 md:p-8"
            onSubmit={handleSubmit(onSubmit)}
          >
            <div className="flex flex-col gap-6">
              {/* header - logo */}
              <div className="flex flex-col items-center text-center gap-2">
                <a
                  href="/"
                  className="mx-auto block w-fit text-center"
                >
                  <img
                    src="/logo.svg"
                    alt="logo"
                  />
                </a>

                <h1 className="text-2xl font-bold">Tạo tài khoản FlowChat</h1>
                <p className="text-muted-foreground text-balance">
                  Chào mừng bạn! Hãy đăng ký để bắt đầu!
                </p>
              </div>

              {/* họ & tên */}
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-2">
                  <Label
                    htmlFor="lastname"
                    className="block text-sm"
                  >
                    Họ
                  </Label>
                  <Input
                    type="text"
                    id="lastname"
                    {...register("lastname")}
                  />

                  {errors.lastname && (
                    <p className="error-message">{errors.lastname.message}</p>
                  )}
                </div>
                <div className="space-y-2">
                  <Label
                    htmlFor="fistname"
                    className="block text-sm"
                  >
                    Tên
                  </Label>
                  <Input
                    type="text"
                    id="firstname"
                    {...register("firstname")}
                  />
                  {errors.firstname && (
                    <p className="error-message">{errors.firstname.message}</p>
                  )}
                </div>
              </div>

              {/* username */}
              <div className="flex flex-col gap-3">
                <Label
                  htmlFor="username"
                  className="block text-sm"
                >
                  Tên đăng nhập
                </Label>
                <Input
                  type="text"
                  id="username"
                  placeholder="flowchat"
                  {...register("username")}
                />
                {errors.username && (
                  <p className="error-message">{errors.username.message}</p>
                )}
              </div>

              {/* email */}
              <div className="flex flex-col gap-3">
                <Label
                  htmlFor="email"
                  className="block text-sm"
                >
                  Email
                </Label>
                <Input
                  type="email"
                  id="email"
                  placeholder="m@gmail.com"
                  {...register("email")}
                />
                {errors.email && (
                  <p className="error-message">{errors.email.message}</p>
                )}
                <p className="text-xs text-muted-foreground">
                  FlowChat sẽ gửi liên kết xác minh tới email này. Bạn phải xác
                  minh trước khi đăng nhập.
                </p>
              </div>

              {/* password */}
              <div className="flex flex-col gap-3">
                <Label
                  htmlFor="password"
                  className="block text-sm"
                >
                  Mật khẩu
                </Label>
                <Input
                  type="password"
                  id="password"
                  {...register("password")}
                />
                {errors.password && (
                  <p className="error-message">{errors.password.message}</p>
                )}
                {password.length > 0 && (
                  <div className="space-y-1.5" aria-live="polite">
                    <div className="flex items-center justify-between text-xs">
                      <span className="text-muted-foreground">Độ mạnh mật khẩu</span>
                      <span className="font-semibold">{strength.label}</span>
                    </div>
                    <div className="h-2 overflow-hidden rounded-full bg-muted">
                      <div
                        className={`h-full rounded-full transition-all ${strength.color}`}
                        style={{ width: strength.width }}
                      />
                    </div>
                    <p className="text-xs text-muted-foreground">
                      Tối thiểu 6 ký tự và có ít nhất một ký tự đặc biệt như @ hoặc !.
                    </p>
                  </div>
                )}
              </div>

              {/* nút đăng ký */}
              <Button
                type="submit"
                className="w-full"
                disabled={isSubmitting}
              >
                Tạo tài khoản
              </Button>

              <div className="flex items-center gap-3 text-xs text-muted-foreground">
                <div className="h-px flex-1 bg-border" />
                hoặc
                <div className="h-px flex-1 bg-border" />
              </div>
              <GoogleSignInButton
                label="signup_with"
                disabled={isSubmitting || loading}
                onCredential={onGoogleCredential}
              />

              <div className="text-center text-sm">
                Đã có tài khoản?{" "}
                <a
                  href="/signin"
                  className="underline underline-offset-4"
                >
                  Đăng nhập
                </a>
              </div>
            </div>
          </form>
          <div className="bg-muted relative hidden md:block">
            <img
              src="/placeholderSignUp.png"
              alt="Image"
              className="absolute top-1/2 -translate-y-1/2 object-cover"
            />
          </div>
        </CardContent>
      </Card>
      <div className=" text-xs text-balance px-6 text-center *:[a]:hover:text-primary text-muted-foreground *:[a]:underline *:[a]:underline-offetset-4">
        Bằng cách tiếp tục, bạn đồng ý với <a href="#">Điều khoản dịch vụ</a> và{" "}
        <a href="#">Chính sách bảo mật</a> của chúng tôi.
      </div>
    </div>
  );
}
