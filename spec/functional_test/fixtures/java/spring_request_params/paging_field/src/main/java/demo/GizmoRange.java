package demo;

import lombok.Getter;
import lombok.Setter;
import org.springframework.data.domain.Sort;

@Getter
@Setter
public class GizmoRange {
    private Integer min;
    private Sort order;
}
