package demo;

import lombok.Getter;
import lombok.Setter;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;

@Getter
@Setter
public class GizmoSearch {
    private String keyword;
    private Pageable pageable;
    private PageRequest pageRequest;
    private Sort ordering;
    private GizmoRange range;
}
