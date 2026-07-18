import { ChevronsUpDown, UserIcon, UserPlus } from "lucide-react";

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from "@/components/ui/sidebar";
import type { User } from "@/types/user";
import Logout from "../auth/Logout";
import { useEffect, useState } from "react";
import FriendRequestDialog from "../friendRequest/FriendRequestDialog";
import ProfileDialog from "../profile/ProfileDialog";
import { useFriendStore } from "@/stores/useFriendStore";

export function NavUser({ user }: { user: User }) {
  const { isMobile } = useSidebar();
  const [friendRequestOpen, setfriendRequestOpen] = useState(false);
  const [profileOpen, setProfileOpen] = useState(false);
  const receivedRequests = useFriendStore((state) => state.receivedList);
  const getAllFriendRequests = useFriendStore(
    (state) => state.getAllFriendRequests
  );
  const requestCount = receivedRequests.length;

  useEffect(() => {
    void getAllFriendRequests();
  }, [getAllFriendRequests]);

  return (
    <>
      <SidebarMenu>
        <SidebarMenuItem>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <SidebarMenuButton
                size="lg"
                className="data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
              >
                <div className="relative">
                  <Avatar className="h-8 w-8 rounded-lg">
                    <AvatarImage
                      src={user.avatarUrl}
                      alt={user.displayName}
                    />
                    <AvatarFallback className="rounded-lg">
                      {user.displayName.charAt(0)}
                    </AvatarFallback>
                  </Avatar>
                  {requestCount > 0 && (
                    <span className="absolute -right-2 -top-2 flex min-w-4 items-center justify-center rounded-full bg-red-500 px-1 text-[10px] font-bold leading-4 text-white ring-2 ring-sidebar">
                      {requestCount > 99 ? "99+" : requestCount}
                    </span>
                  )}
                </div>
                <div className="grid flex-1 text-left text-sm leading-tight">
                  <span className="truncate font-medium">{user.displayName}</span>
                  <span className="truncate text-xs">{user.username}</span>
                </div>
                <ChevronsUpDown className="ml-auto size-4" />
              </SidebarMenuButton>
            </DropdownMenuTrigger>
            <DropdownMenuContent
              className="w-(--radix-dropdown-menu-trigger-width) min-w-56 rounded-lg"
              side={isMobile ? "bottom" : "right"}
              align="end"
              sideOffset={4}
            >
              <DropdownMenuLabel className="p-0 font-normal">
                <div className="flex items-center gap-2 px-1 py-1.5 text-left text-sm">
                  <Avatar className="h-8 w-8 rounded-lg">
                    <AvatarImage
                      src={user.avatarUrl}
                      alt={user.username}
                    />
                    <AvatarFallback className="rounded-lg">
                      {user.displayName.charAt(0)}
                    </AvatarFallback>
                  </Avatar>
                  <div className="grid flex-1 text-left text-sm leading-tight">
                    <span className="truncate font-medium">{user.displayName}</span>
                    <span className="truncate text-xs">{user.username}</span>
                  </div>
                </div>
              </DropdownMenuLabel>
              <DropdownMenuSeparator />
              <DropdownMenuGroup>
                <DropdownMenuItem onClick={() => setProfileOpen(true)}>
                  <UserIcon className="text-muted-foreground dark:group-focus:!text-accent-foreground" />
                  Tài Khoản
                </DropdownMenuItem>
                <DropdownMenuItem onClick={() => setfriendRequestOpen(true)}>
                  <UserPlus className="text-muted-foreground dark:group-focus:!text-accent-foreground" />
                  <span className="flex-1">Lời mời kết bạn</span>
                  {requestCount > 0 && (
                    <span className="flex min-w-5 items-center justify-center rounded-full bg-red-500 px-1.5 text-[11px] font-bold leading-5 text-white">
                      {requestCount > 99 ? "99+" : requestCount}
                    </span>
                  )}
                </DropdownMenuItem>
              </DropdownMenuGroup>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                className="cursor-pointer"
                variant="destructive"
              >
                <Logout />
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </SidebarMenuItem>
      </SidebarMenu>

      <FriendRequestDialog
        open={friendRequestOpen}
        setOpen={setfriendRequestOpen}
      />

      <ProfileDialog
        open={profileOpen}
        setOpen={setProfileOpen}
      />
    </>
  );
}
