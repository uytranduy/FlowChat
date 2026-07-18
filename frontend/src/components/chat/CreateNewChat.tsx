import { useFriendStore } from "@/stores/useFriendStore";
import { Card } from "../ui/card";
import { Dialog, DialogTrigger } from "../ui/dialog";
import { MessageCircle } from "lucide-react";
import FriendListModal from "../createNewChat/FriendListModal";
import { useState } from "react";

const CreateNewChat = () => {
  const { getFriends } = useFriendStore();
  const [open, setOpen] = useState(false);

  const handleOpenChange = (nextOpen: boolean) => {
    setOpen(nextOpen);
    if (nextOpen) void getFriends();
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        <Card className="flex-1 cursor-pointer p-3 glass transition-smooth hover:shadow-soft group/card">
            <div className="flex items-center gap-4">
              <div className="size-8 bg-gradient-chat rounded-full flex items-center justify-center group-hover/card:scale-110 transition-bounce">
                <MessageCircle className="size-4 text-white" />
              </div>
              <span className="text-sm font-medium capitalize">
                gửi tin nhắn
              </span>
            </div>
        </Card>
      </DialogTrigger>
      <FriendListModal onSelected={() => setOpen(false)} />
    </Dialog>
  );
};

export default CreateNewChat;
