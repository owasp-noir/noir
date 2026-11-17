package demo;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Setter;

public class GadgetForm {
    public String label;
    public transient String computedLabel;
    private transient int viewCount;
    private transient String nickname;
    @JsonProperty public transient String pinned;
    @Setter private transient String tag;

    public void setNickname(String nickname) { this.nickname = nickname; }
}
